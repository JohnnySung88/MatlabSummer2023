function [Time,Biterror,Capacity_sum,Rx1_SNR,Rx2_SNR,Lena_RGB] = Rx_fun(Rx_signal,DTinfo)
	load('frame_data.mat');
	Fs 	= frame_data.Fs;
	Tx	= frame_data.Tx;
	Rx  = frame_data.Rx;
	
	tic;
	
	y = Rx_signal;%2*1228800
	%CFO估測(需多重路徑猜測)
	CFO_ignore 		= frame_data.CFO_ignore;
	hat_delta_f_sym = zeros(560,2);
	index  			= 1;
	CFO_sum	 		= 0;
	CP_num			= 0;
	t 				= 0:(10e-3/1228800):10e-3;
	t 				= t(2:1228801);				%移除第一個位置資料
	
	for symbol = 1:560
		if (mod(symbol,28)-1)%size 144
			CFO_head = y( : , index+CFO_ignore     : index+143      );
			CFO_tail = y( : , index+CFO_ignore+2048: index+143+2048 );
			CFO_sum	 = CFO_sum+ sum(CFO_head .* (CFO_tail').','all');
			CP_num	 = CP_num + 144 - CFO_ignore;
			index    = index + 144 + 2048;
		else				 %size 208
			CFO_head = y( : , index+CFO_ignore     : index+207      );
			CFO_tail = y( : , index+CFO_ignore+2048: index+207+2048 );
			CFO_sum	 = CFO_sum+ sum(CFO_head .* (CFO_tail').','all');
			CP_num	 = CP_num + 208 - CFO_ignore;
			index    = index + 208 + 2048;
		end
	end
	hat_delta_f = -(Fs/2048) * angle( CFO_sum/CP_num )/(2*pi) ;
	%CFO補償
	y = y ./ exp( 1i * 2 * pi * hat_delta_f * t);
	%移除CP
	y_rmCP		= zeros(2048 , 560, Tx);
	index  = 1;
	for symbol = 1:560
		if (mod(symbol,28)-1)
			for ram = 1:Rx
				y_rmCP(:,symbol,ram) = y(ram,index+144:index+144+2048-1);
			end
			index  = index+144+2048;
		else
			for ram = 1:Rx
				y_rmCP(:,symbol,ram) = y(ram,index+208:index+208+2048-1);
			end
			index  = index +208+2048;
		end
	end
	%FFT----以下為頻域
	Y_fft 	= fftshift( fft( y_rmCP/sqrt(2048) ) ,1);
	%rm Guard Band
	Y	  		= [ Y_fft( 203:1024,:,:) ; Y_fft( 1026:1847,:,:) ];
	%LMMSE估測
	DMRS_DATA 	= +0.7071 + 0.7071*1i ;
	Y_DMRS 		= Y(2:2:1644 , 3:14:560,:);
	H_LMMSE			 = zeros(1644,40,2,2);
	H_LMMSE(:,:,1,1) = frame_data.LMMSE(:,:,1,1) * (DMRS_DATA' .*Y_DMRS(:,:,1));
	H_LMMSE(:,:,2,1) = frame_data.LMMSE(:,:,2,1) * (DMRS_DATA' .*Y_DMRS(:,:,2));
	H_LMMSE(:,:,1,2) = frame_data.LMMSE(:,:,1,2) * (DMRS_DATA' .*Y_DMRS(:,:,1));
	H_LMMSE(:,:,2,2) = frame_data.LMMSE(:,:,2,2) * (DMRS_DATA' .*Y_DMRS(:,:,2));
	%線性內差(LMMSE only)
	DMRS_Spos	= 3:14:560;
	H_INTER		= zeros(1644,560,2,2);	
	for symbol  = 549:560  %邊界
		head_dist	= symbol - 549;
		back_dist	= 563    - symbol;
		H_INTER(:,symbol,:,:) = ( back_dist * H_LMMSE(:,40,:,:) + head_dist * H_LMMSE(:,1,:,:)  )  /14;
	end
	for symbol  = 1:2     %邊界
		head_dist	= 11 + symbol;
		back_dist	= 3  - symbol;
		H_INTER(:,symbol,:,:) = ( back_dist * H_LMMSE(:,40,:,:) + head_dist * H_LMMSE(:,1,:,:)  )  /14;
	end
	for symbol 	= 3:548  %連續
		pos  		= floor((symbol-3)/14) + 1;
		head_dist	= symbol 			- DMRS_Spos(pos);
		back_dist	= DMRS_Spos(pos+1) 	- symbol;
		H_INTER(:,symbol,:,:) = ( back_dist * H_LMMSE(:,pos,:,:) + head_dist * H_LMMSE(:,pos+1,:,:)  )  /14;
	end
	%雜訊估測
	DMRS  		= frame_data.DMRS;
	DMRS_H		= H_LMMSE (2:2:1644,:,:,:);
	DMRS_hat_Y  = zeros(822,40,2);
	for SC = 1:822
		for symbol = 1:40
			DMRS_hat_Y(SC,symbol,:) = reshape(DMRS_H(SC,symbol,:,:),2,2) * reshape(DMRS(SC,symbol,:),2,1);
		end
	end
	Rx1_No = sum( abs( Y_DMRS(:,:,1)  - DMRS_hat_Y(:,:,1) ).^2 ,'all' )/(40*822);
	Rx2_No = sum( abs( Y_DMRS(:,:,2)  - DMRS_hat_Y(:,:,2) ).^2 ,'all' )/(40*822);
	%detector
	switch DTinfo
		case 'LMMSE'
			norm_Y = zeros(1644,560,2);
			norm_H = zeros(1644,560,2,2);
			norm_Y(:,:,1)   = Y(:,:,1)          ./ Rx1_No;
			norm_Y(:,:,2)   = Y(:,:,2)          ./ Rx2_No;
			norm_H(:,:,1,:) = H_INTER(:,:,1,:)  ./ Rx1_No;
			norm_H(:,:,2,:) = H_INTER(:,:,2,:)  ./ Rx2_No;
			X_hat = LMMSE(norm_Y,norm_H,Tx);
			X_hat = X_hat/frame_data.NF;
		case 'ZF'
			X_hat = ZF_detector(Y,H_INTER,Tx);
			X_hat = X_hat/frame_data.NF;
	end
	%反解資料
	LDPC_mod_L_hat	= X_hat(frame_data.DATA_Pos);
	LDPC_mod_L_hat  = LDPC_mod_L_hat(1:1770336);%magic num
	%解碼
	LDPC_dec_L_hat = qamdemod(LDPC_mod_L_hat,frame_data.QAM  ,'gray');		
	LDPC_bin_L_hat = reshape(dec2bin (LDPC_dec_L_hat,frame_data.q_bit).' - '0',[],1) ;
	LDPC_bin_part  = reshape(LDPC_bin_L_hat,[],1296);
	LDPC_bin_part  = permute(LDPC_bin_part ,[2,1]);
	Lena_bin_hat  = reshape(LDPC_bin_part(1:648,:).',[],8);
	%Time
	Time = toc;
	%noLDPC decode(image)
	bin_table	= 2 .^ (7:-1:0);
	Lena_row = frame_data.Lena_row;
	Lena_col = frame_data.Lena_col;
	Lena_size= frame_data.Lena_size;
	Lena_bin_hat = Lena_bin_hat(1:Lena_size,:);
	Lena_dec_hat = sum(Lena_bin_hat.*bin_table,2);%bin2dec
	Lena_Csize	 = Lena_row*Lena_col;
	Lena_RGB	 = zeros(Lena_row,Lena_col,3);
	Lena_RGB(:,:,1) = reshape( Lena_dec_hat(             1:Lena_Csize  ) ,Lena_row,Lena_col);
	Lena_RGB(:,:,2) = reshape( Lena_dec_hat(Lena_Csize  +1:Lena_Csize*2) ,Lena_row,Lena_col);
	Lena_RGB(:,:,3) = reshape( Lena_dec_hat(Lena_Csize*2+1:Lena_Csize*3) ,Lena_row,Lena_col);
	Lena_RGB		= uint8(Lena_RGB);
	%BER
	Biterror = sum(Lena_bin_hat ~= frame_data.Lena_bin,'all');
	%SNR
	Rx1_SNR  = -10*log10(Rx1_No );
	Rx2_SNR  = -10*log10(Rx2_No );
	%Capacity
	No = (Rx1_No+Rx2_No)/2;
	SNR = 1/No;
	Capacity_sum = 0;
	for SC = 1:1644
		for slot = 1:560
			unit_H 	 = reshape(H_INTER(SC,slot,:,:),Rx,Tx);
			Capacity_sum = Capacity_sum + abs( log2( det( eye(Tx) + (1/Tx) .* SNR .* (unit_H*unit_H'))));
		end
	end
end

