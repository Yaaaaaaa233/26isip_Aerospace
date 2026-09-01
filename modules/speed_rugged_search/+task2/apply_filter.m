function y = apply_filter(x, method, w)
%APPLY_FILTER Centered symmetric filters for scan-series smoothing.
% 全部为中心对称奇数窗口：对对称特征零相位偏移(无平移最优点的首要保证)。
% x: 沿扫描序(等间距)的测量序列；method: none/moving/gaussian/median/sg。
% 边缘处理：窗口收缩(两侧用可用样本)，避免任务1式边缘拖尾偏置。
x = x(:)';
n = numel(x);
w = min(w, 2*floor(n/2)+1);
half = floor(w/2);
y = zeros(1,n);
switch method
    case 'none'
        y = x;
    case 'moving'
        for i=1:n
            lo=max(1,i-half); hi=min(n,i+half);
            y(i)=mean(x(lo:hi));
        end
    case 'gaussian'
        sigma=max(half/2,0.6);
        for i=1:n
            lo=max(1,i-half); hi=min(n,i+half);
            g=exp(-((lo:hi)-i).^2/(2*sigma^2));
            y(i)=sum(x(lo:hi).*g)/sum(g);
        end
    case 'median'
        for i=1:n
            lo=max(1,i-half); hi=min(n,i+half);
            y(i)=median(x(lo:hi));
        end
    case 'sg'
        % Savitzky-Golay 简化实现：窗口内二次多项式拟合取中心值(保曲率)。
        % 边缘用反射填充(对称, 零边缘偏置)，避免降阶拟合的不对称拖尾。
        if n>half+1
            xp=[x(half+1:-1:2), x, x(end-1:-1:end-half)];
        else
            xp=repmat(x,1,ceil((2*half+1)/n)+1);
        end
        for i=1:n
            idx=-half:half;
            p=polyfit(idx,xp(i:i+2*half),2);
            y(i)=polyval(p,0);
        end
    otherwise
        error('task2:Filter','Unknown filter method: %s',method);
end
end
