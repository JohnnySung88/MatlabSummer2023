%2x2MIMO LDPC
clear
clc

%假設規範
frame_num 	= 500;
code_rate=0.5;
SNR_in_dB 	= 0:5:40;
SNR_weight 	= 45;
window 		= 10;
DMRS_DATA 	= +0.7071 + 0.7071*1i ;
Fs			= 122.88e6;
delta_f		= 1000;
load('LDPC_11nD2_1296b_R12.mat');

Tx		  	= 2;
Rx		  	= 2;
QAM 	= 16;
q_bit 	= log2(QAM);
Eavg 	= (qammod([0:QAM-1],QAM) * qammod([0:QAM-1],QAM)') / QAM;
%Eavg = mean(abs(qammod([0:QAM-1], QAM)).^2);
NF 		= 1 / sqrt(Eavg);

%LMMSE init
N_fft 	=2048;
R_HD_HD	=zeros(822,822);
R_H_HD	=zeros(1644,822);
DMRS_pos=[204:2:1024,1027:2:1847];
Real_pos=[203:1:1024,1026:1:1847];
for p=1:822
	for k=1:822
		if DMRS_pos(k)==DMRS_pos(p)
			R_HD_HD  (k,p)=1;
		else
			R_HD_HD  (k,p)=( 1 - exp( -1i*2*pi*window*(DMRS_pos(k)-DMRS_pos(p))/N_fft ) )/( 1i*2*pi*window*(DMRS_pos(k)-DMRS_pos(p))/N_fft );
		end
	end
	for k=1:1644
		if Real_pos(k)==DMRS_pos(p)
			R_H_HD(k,p)=1;
		else
			R_H_HD(k,p)=( 1 - exp( -1i*2*pi*window*(Real_pos(k)-DMRS_pos(p))/N_fft ) )/( 1i*2*pi*window*(Real_pos(k)-DMRS_pos(p))/N_fft );
		end
	end
end
SNR_W 	= 10^( SNR_weight /10);

%LDPC init
HLDPC = double(LDPC.H.x);
[row,col]	= find(HLDPC==1);
[A,I] = sort(row);
[B,I2] = sort(col);

H_row_master 	  = zeros(648,8);
H_row_master_size = ones(648,1);

for i=1:4644
    H_row_master( A(i) , H_row_master_size( A(i)) ) = col(I(i));
    H_row_master_size(A(i)) = H_row_master_size(A(i)) + 1;
end
H_row_master_size = H_row_master_size - 1;

%Result Subtract init 
Result=zeros(1,length(SNR_in_dB));
QAM_bin=zeros(frame_num,length(SNR_in_dB));
LLR_bin=zeros(frame_num,length(SNR_in_dB));
LDPC_bin=zeros(frame_num,length(SNR_in_dB)); %binary_OMS

for time=1:length(SNR_in_dB)
	SNR = 10^( SNR_in_dB(time)/10);
	No  = 10^(-SNR_in_dB(time)/10);
    LLR_BER = 0;
	LDPC_BER = 0;
    parfor frame=1:frame_num
        fprintf("SNR : %d/%d Frame : %d/%d\n\n",time,length(SNR_in_dB),frame,frame_num);	
		%輸入資料(含DMRS)
		dec_data	= randi  ([0,QAM-1],Tx*(1644*560-822*40)*code_rate,1); %只能傳送CODERATE的資訊量
		%data_mod_L	= qammod (dec_data,QAM,'gray')*NF;
		dou_data    = dec2bin(dec_data,q_bit)-'0'; %轉double
		dou2_data   = reshape(dou_data.',Tx*(1644*560-822*40)*code_rate*q_bit,1);
		Matrix_data = reshape(dou2_data,648,5480);
		%data_bin 	= dec2bin(dec_data,q_bit);
		%data_mod	= zeros(1644,560,2);
        
		LDPC_bin_Matrix= mod(Matrix_data.'* double(LDPC.G.x),2) ;
        LDPC_dec=reshape([8 4 2 1]*reshape(LDPC_bin_Matrix.',4,[]),[],1);   %二進位轉十進位
        LDPC_mod= qammod(LDPC_dec,QAM)*NF;
        LDPC_mod_data=zeros(1644,560,2);
		index		= 1;
		for symbol=1:560
			if mod( (symbol - 3) , 14) == 0
				data_range 		     = reshape(LDPC_mod(index:index+ 822*Tx-1),1, 822,Tx );
				LDPC_mod_data(:,symbol,:) = reshape([ data_range  ; DMRS_DATA * ones(1,822,Tx)],1644,2);
				index				 = index + 822*Tx;
			else
				LDPC_mod_data(:,symbol,:) = reshape(LDPC_mod(index:index+1644*Tx-1),1644,Tx );
				index				 = index + 1644*Tx;
			end
		end
		
		%CDM
		LDPC_mod_data(2:4:1644,3:14:560,2) = -LDPC_mod_data(2:4:1644,3:14:560,2);
		%data_mod(2:4:1644,3:14:560,2:2:Tx) = -data_mod(2:4:1644,3:14:560,2:2:Tx);

		%Guard Band
		GBhead=zeros(202,560,Tx);
        GBtail=zeros(201,560,Tx);
		DC =   zeros(1,560,Tx);
		X =[GBhead;LDPC_mod_data(1:822,:,:) ;DC ;LDPC_mod_data(823:end,:,:) ;GBtail];
		%IFFT
		x  = ifft(ifftshift(X,1))*sqrt(2048);	%2048 x 14*4*10						
		%CP
		x_CP = zeros(1,1228800,Tx);
		index=1;
		for symbol=1:14*4*10
			if	mod(symbol,28)-1
				x_CP(1, index:index+2048+144-1,:)=[ x(2048-144+1:2048,symbol,:) ; x(:,symbol,:)];
				index = index+2048+144;
			else
				x_CP(1, index:index+2048+208-1,:)=[ x(2048-208+1:2048,symbol,:) ; x(:,symbol,:)];
				index = index+2048+208;
			end
		end
		%通道
		PowerdB 	= [ -2 -8 -10 -12 -15 -18].';
		PowerdB_MIMO= repmat(PowerdB,1,Rx,Tx);
		H_Channel 	= sqrt(10.^(PowerdB_MIMO./10)).* sqrt( 1/ Tx );
		Ntap		= length(PowerdB);
		H_Channel   = H_Channel .* ( sqrt( 1/2 ) .* ( randn(Ntap,Rx,Tx) + 1i*randn(Ntap,Rx,Tx) ) );
		%捲積
		pure_y		= zeros(Rx,1228800+5);
		for Tx_n = 1:Tx
			for Rx_n = 1:Rx
				pure_y(Rx_n,:) = pure_y(Rx_n,:) + conv( x_CP(1,:,Tx_n) , H_Channel(:,Rx_n,Tx_n) );
			end
		end
        pure_y(:,1228801:end) = [];	%刪除最後5筆資料
		%產生訊號
		n 			= sqrt(No/2) *( randn(Tx,1228800) + randn(Tx,1228800)*1i );% randn產生noise variance=No
		y			= pure_y + n;
		%移除CP
		y_rmCP		= zeros(2048 , 560, Tx);
		index2  = 1;
		for symbol = 1:560
			if (mod(symbol,28)-1)
				for ram = 1:Rx
					y_rmCP(:,symbol,ram) = y(ram,index2+144:index2+144+2048-1);
				end
				index2  = index2+144+2048;
			else
				for ram = 1:Rx
					y_rmCP(:,symbol,ram) = y(ram,index2+208:index2+208+2048-1);
				end
				index2  = index2 +208+2048;
			end
		end
		%FFT----以下為頻域
		Y_fft 	= fftshift( fft( y_rmCP/sqrt(2048) ) ,1);
		%rm Guard Band
		Y	  	= [ Y_fft( 203:1024,:,:) ; Y_fft( 1026:1847,:,:) ];

		h = [H_Channel ; zeros(2042,2,2)];
        H = fftshift(fft(h,[],1),1);
        H_Data 	= [H(203:1024,:,:);H(1026:1847,:,:)];
        H_frame = permute(repmat( H_Data(:,:,:),1,1,1,560),[1 4 2 3]  );
		%取得LMMSE估測結果
		Y_DMRS 			 = Y(2:2:1644 , 3:14:560,:);
		P0 				 = eye(822);
		P1 				 = ones(822,1);
		P1(1:2:822) = -1;
		P1 				 = diag(P1);
		H_LMMSE			 = zeros(1644,40,2,2);
		H_LMMSE(:,:,1,1) = R_H_HD* P0' * inv( P0*R_HD_HD*P0' + P1*R_HD_HD*P1' + (1/SNR_W)*eye(822) ) * (DMRS_DATA' .*Y_DMRS(:,:,1));
		H_LMMSE(:,:,2,1) = R_H_HD* P0' * inv( P0*R_HD_HD*P0' + P1*R_HD_HD*P1' + (1/SNR_W)*eye(822) ) * (DMRS_DATA' .*Y_DMRS(:,:,2));
		H_LMMSE(:,:,1,2) = R_H_HD* P1' * inv( P0*R_HD_HD*P0' + P1*R_HD_HD*P1' + (1/SNR_W)*eye(822) ) * (DMRS_DATA' .*Y_DMRS(:,:,1));
		H_LMMSE(:,:,2,2) = R_H_HD* P1' * inv( P0*R_HD_HD*P0' + P1*R_HD_HD*P1' + (1/SNR_W)*eye(822) ) * (DMRS_DATA' .*Y_DMRS(:,:,2));
		%線性內差
		DMRS_Spos	= 3:14:560;
		H_INTER		= zeros(1644,560,2,2);
        for symbol = 1:560
            if symbol >= 1 && symbol <= 2 %前界
                head_dist	= 11 + symbol;
			    back_dist	= 3  - symbol;
                H_INTER(:,symbol,:,:) = (head_dist * H_LMMSE(:,1,:,:))/14+(back_dist * H_LMMSE(:,40,:,:))/14;
            end
            if symbol >= 3 && symbol <= 548  %中界
			    pos  		= floor((symbol-3)/14) + 1;
			    head_dist	= symbol 			- DMRS_Spos(pos);
			    back_dist	= DMRS_Spos(pos+1) 	- symbol;
                H_INTER(:,symbol,:,:) = (head_dist * H_LMMSE(:,pos+1,:,:))/14+(back_dist * H_LMMSE(:,pos,:,:))/14;
            end
            if symbol >= 549 && symbol <= 560 %後界
			    head_dist	= symbol - 549;
			    back_dist	= 563    - symbol;
                H_INTER(:,symbol,:,:) = (head_dist * H_LMMSE(:,1,:,:))/14+(back_dist * H_LMMSE(:,40,:,:))/14;
            end
        end
     
		%雜訊估測
		DMRS  		= LDPC_mod_data(2:2:1644 , 3:14:560,:);
		DMRS_H		= H_LMMSE (2:2:1644,:,:,:);
		DMRS_hat_Y  = zeros(822,40,2);
		for SC = 1:822
			for symbol = 1:40
				DMRS_hat_Y(SC,symbol,:) = reshape(DMRS_H(SC,symbol,:,:),2,2) * reshape(DMRS(SC,symbol,:),2,1);
			end
		end
		Rx1_No = sum( abs( Y_DMRS(:,:,1)  - DMRS_hat_Y(:,:,1) ).^2 ,'all' )/(40*822);
		Rx2_No = sum( abs( Y_DMRS(:,:,2)  - DMRS_hat_Y(:,:,2) ).^2 ,'all' )/(40*822);
        norm_Y = zeros(1644,560,2);
		norm_H = zeros(1644,560,2,2);
		norm_Y(:,:,1)   = Y(:,:,1)          ./ Rx1_No;
        norm_Y(:,:,2)   = Y(:,:,2)          ./ Rx2_No;
        norm_H(:,:,1,:) = H_INTER(:,:,1,:)  ./ Rx1_No;
        norm_H(:,:,2,:) = H_INTER(:,:,2,:)  ./ Rx2_No;

        % ZF
        %X_ZF=zeros(1644,560,Tx);
        %for carrier=1:1644
            %for slot =1:560
                %ZF_temp=zeros(Tx,1);
                %H_temp=squeeze(norm_H(carrier,slot,:,:));  %變成二維
                %Y_temp=squeeze(norm_Y(carrier,slot,:));    %變成一維
                %ZF_temp=ZF_temp+(inv(H_temp'*H_temp)*H_temp')*Y_temp;      %inv(H'H)H'y
                %X_ZF(carrier,slot,:)=ZF_temp;
            %end
        %end
        %X_ZF = X_ZF/NF;

        X_ZF = ZFD(norm_Y,norm_H,Tx);
        X_ZF = X_ZF/NF;

        %LMMSE
        %X_ZF = LMMSE(norm_Y,norm_H,Tx);
        %X_ZF = X_ZF/NF;

		%反解資料
		data_mod_ZF 	= zeros(Tx*(1644*560-822*40),1);
		index			= 1;
		for symbol=1:560
			if mod( (symbol - 3) , 14) == 0
				data_mod_ZF(index:index+ 822*Tx-1)	 = reshape(X_ZF(1:2:1644,symbol,:), 822*Tx,1 );
				index				 = index + 822*Tx;
			else
				data_mod_ZF(index:index+1644*Tx-1)	 = reshape(X_ZF(1:1:1644,symbol,:),1644*Tx,1 );
				index				 = index + 1644*Tx;
			end
		end
		
		%做LLR
		y_in  = real(data_mod_ZF);	%LLR inphase
		y_qu  = imag(data_mod_ZF);  %LLR quadrature
		%y_LLR = zeros(length(data_mod_ZF),q_bit); %LLR output
		y_LLR = zeros(q_bit*length(data_mod_ZF),1);

		y_LLR(1:4:length(y_LLR))=(1/(2*No)) * (min ( (y_in-  1) .^2 , ( y_in-  3) .^2 ) -min  ( (y_in-(-1)).^2 , ( y_in-(-3)).^ 2));
        y_LLR(2:4:length(y_LLR))=(1/(2*No)) * (min ( (y_in-(-1)).^2 , ( y_in-  1) .^2 ) -min  ( (y_in-(-3)).^2 , ( y_in-  3 ).^ 2));
        y_LLR(3:4:length(y_LLR))=(1/(2*No)) * (min ( (y_qu-(-1)).^2 , ( y_qu-(-3)).^2 ) -min  ( (y_qu-  1) .^2 , ( y_qu-  3 ).^ 2));
        y_LLR(4:4:length(y_LLR))=(1/(2*No)) * (min ( (y_qu-(-1)).^2 , ( y_qu-  1) .^2 ) -min  ( (y_qu-(-3)).^2 , ( y_qu-  3 ).^ 2));

		y_LLR= reshape(y_LLR,1296,5480);
        LLR_OMS= LDPC_OMS(y_LLR,H_row_master,H_row_master_size);
        data_bin_LLR= reshape(y_LLR (1:648,:),[],1)<0;
        data_bin_OMS= reshape(LLR_OMS(1:648,:),[],1)<0;
		
		%demod binary_data
		%data_dec_ZF = qamdemod(data_mod_ZF,QAM,'gray');
		%data_bin_ZF = dec2bin (data_dec_ZF,q_bit);
		%data_bin_ZF  = data_bin_ZF-'0'; %ASCII code char轉double
		%Result(1,time) = mse(data_bin_ZF,y_LLR);
		LLR_BER=LLR_BER+sum(sum(dou2_data~= data_bin_LLR),'all');
        LDPC_BER=LDPC_BER+sum(sum(dou2_data~= data_bin_OMS),'all');
        %LLR_BER = LLR_BER + sum(sum((data_bin-'0') ~= y_LLR),'all');
    end
	LLR_bin(1,time) =LLR_BER/(1644*560*q_bit*frame_num*Tx);
	LDPC_bin(1,time)=LDPC_BER/(1644*560*q_bit*frame_num*Tx);
end

figure(1)
semilogy(SNR_in_dB,LLR_bin(1,:),'b-','LineWidth',2)
hold on
semilogy(SNR_in_dB,LDPC_bin(1,:),'r--','LineWidth',2)
hold on
grid on
axis tight
title('LLR vs LDPC')
xlabel('SNR (dB)')
ylabel('BER')
legend('LLR','LDPC(OMS)')