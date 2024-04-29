%% N-step ahead predictor
clc; close all; clear all;

M = 1.   ;       % mass of the pendulum
L = 1.   ;       % lenght of the pendulum
b = 0.1  ;       % friction coefficient
g = 9.81  ;      % acceleration of gravity
J = 1/3*M*L^2 ;  % moment of inertia
Ts = 1/30;

Tlength = 200;              % Experiment length
lambda = 1e+10;              % Cost for the initial condition
r = 0*ones(Tlength,1);      % Reference signal


% Load the weigths of the neural network:
load('data/weight1.mat')
load('data/weight2.mat')
load('data/weight3.mat')
weights = struct('weight1',weight1,'weight2',weight2,'weight3',weight3);

% Dimensions of the network
n_basis = length(weight1(:,1));         % Number of neurons per layer
Tini = (length(weight1(1,:))+1)/2;      % Number of time shifts for inputs and outputs
N = length(weight3(:,1));               % Prediction horizon
Q = 10*eye(n_basis); 
R=  0.01;
Pin = 1/10000;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Relearn P %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
load('data/invariant.mat')    % Load the invariant set and cost matrices

O_var = sdpvar(n_basis,n_basis,'symmetric','real')

M_var = [O_var,             (A*O_var+B*K*O_var).',      O_var,                      (K*O_var).';
    (A*O_var+B*K*O_var),    O_var,                      zeros(n_basis,n_basis),     zeros(n_basis,1);
    O_var,                  zeros(n_basis,n_basis),     inv(Q),                     zeros(n_basis,1);
    K*O_var,                zeros(1,n_basis),           zeros(1,n_basis),           inv(R)]


objective = [norm(O_var - Pin*eye(n_basis))];
constraints = [M_var >= 0.000001*eye(1)];
options = sdpsettings('solver', 'mosek', 'verbose', 0, 'debug', 0)

optimize(constraints,objective,options)

O_opt = value(O_var)
P = inv(O_opt)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Simulate the system
Psi = kron(eye(N), R);
Omega = kron(eye(N), Q)
Omega = blkdiag(Omega(1:end-n_basis,1:end-n_basis),P)

%% Simulate the system
u = sdpvar(N,1);                        % Input variable
Z = sdpvar(N*n_basis,1);                % Koopman state variable
nl_part = sdpvar(length(weight2),1);    % True initial condition system
z_part = sdpvar(length(weight2),1);     % Shifted predicted initial condition
z0 = sdpvar(length(weight2),1);         % Initial condition applied to the MPC problem
xi = sdpvar(1,1);                       % Interpolation variable for initial condition

% Cost function:
objective = Z'*Omega*Z+(u)'*Psi*(u) + z0'*Q*z0 + lambda*(z_part-nl_part)'*(z_part-nl_part)*xi^2;  

% Constraints:
constraints = [z0 == (1-xi)*nl_part + xi*z_part];                   % Initial condition 
constraints = [constraints, 0<=xi<=1];                              % Constraint for interpollation variable
constraints = [constraints, MN*Z((end-n_basis+1):end,1)<=bN];       % Terminal constraint 
constraints = [constraints, Z == Theta*[z0;u]];                     % Predicted state sequence
for k = 1:N
    constraints = [constraints,  -3<=u(k)<=3];                      % Input constraint
end
Parameters = {nl_part,z_part};
Outputs = {u,Z,xi,z0};

% Select the solver and problem settings:
options = sdpsettings('solver', ['QUADPROG' ...
    ''], 'verbose', 0, 'debug', 0);
% Define the problem:
controller = optimizer(constraints, objective, options, Parameters, Outputs);

%% initial conditions
y(1) = 0.2;
xx2(1) = y(1);
xx1(1) = 7;
u_mpc = 0;
u = [];
th=[];
NL_part_all = [];
Z0 = [];
E_k = [];
t_vec = 0

y_ini = ones(Tini,1)*y(1)
u_ini = zeros(Tini-1,1)
%%
for i = 1:length(r)-N;
i
t_vec(i+1) = i*Ts;
tic;
if i == 1
y_ini = [y_ini(2:end);y(i)];
u_ini = u_ini;
end
if i >= 2 
y_ini = [y_ini(2:end);y(i)];
u_ini = [u_ini(2:end);u(i-1)];
end

clear Nl_part;
Nl_part = [];
out =  tanh(weight1*[u_ini;y_ini]);  
Nl_part =  tanh(weight2*out);  

NL_part_all = [NL_part_all, Nl_part];

if i < Tini 
Z_part = Nl_part;
else 
Z_part = Zkm1;
E_k = [E_k, (Zkm1-Nl_part)];
end 

%%% mpc sol
Nl_part = double(Nl_part);
Z_part = double(Z_part);

OUT = controller({Nl_part,Z_part});

Uk = OUT{1};
Zkm1 = OUT{2}(1:n_basis);
Xi(i) = OUT{3};
Z0 = [Z0,OUT{4}];

u_mpc = Uk(1);
u = [u u_mpc];
th=[th;toc];

%%% output update
xx1(i+1) = xx1(i)-b*Ts/J*xx1(i)-Ts*M*L*g/(2*J)*sin(xx2(i))+Ts/J*u(i);
xx2(i+1) = xx2(i)+Ts*xx1(i);
y(i+1) = xx2(i+1);

end

%% New plot
load('data/SPC.mat')
load('data/NMPC.mat')

curr_fig = figure;
curr_axes1=axes('Parent',curr_fig,'FontSize',11,'FontName','Times New Roman');
box(curr_axes1,'on');
hold(curr_axes1,'all');
%your plots
subplot(2,1,1)
hold on;
plot(t_vec,r(1:length(t_vec)),'LineWidth',3,'Color',"#7E2F8E");
plot(t_vec,y,'LineWidth',3,'Color',"#0072BD");
% plot(t_SPC,ySPC,'LineWidth',3,'Color',"#EDB120");
plot(t_vec_NMPC,yNMPC,'LineWidth',3,'Color',"#EDB120");
legend('','KDPC','SPC','NMPC','Location','northeast');
ylabel('$x_2$',Interpreter='latex')
axis tight 
grid on
xlim([0,3])
subplot(2,1,2)
hold on;
plot(t_vec(1:length(u)),u,'LineWidth',3,'Color',"#0072BD");
% plot(t_SPC(1:end-1),uSPC,'LineWidth',3,'Color',"#EDB120");
plot(t_vec_NMPC(1:end-1),uNMPC,'LineWidth',3,'Color',"#EDB120");
legend('KDPC','SPC','NMPC','','','Location','northeast');
ylabel('$u$',Interpreter='latex')
axis tight 
grid on;
xlim([0,3])
%your plots
set(gca,'TickLabelInterpreter','Latex')
set(curr_fig,'Units','centimeters','PaperSize',[20.98 29.68],'PaperUnits','centimeters','PaperPosition',[0 0 12 8])
% you can change 9 and 6.3 to change the ratios of the plot...
savefig('figures/pendulum.fig') %change it with the name you want to give to the .fig plot
print -depsc figures/pendulum %change it with the name you want to give to the .eps figure



curr_fig = figure;
curr_axes1=axes('Parent',curr_fig,'FontSize',11,'FontName','Times New Roman');
box(curr_axes1,'on');
hold(curr_axes1,'all');
%your plots
subplot(3,1,1)
plot(t_vec(1:end-1),Xi,'LineWidth',3,'Color',"#0072BD")
ylabel('$\xi$',Interpreter='latex')
grid on;
xlim([0,3])
subplot(3,1,2)
hold on
for i = 1:length(NL_part_all(:,1))
plot(t_vec(1:end-1),NL_part_all(i,:),'LineWidth',3)
end
ylabel('$\varphi_i$',Interpreter='latex')
axis tight 
grid on;
xlim([0,3])
subplot(3,1,3)
hold on
for i = 1:length(NL_part_all(:,1))
plot(t_vec(1:end-Tini),E_k(i,:),'LineWidth',3)
end
ylabel('$(e(k))$',Interpreter='latex')
xlabel('$t [s]$',Interpreter='latex')
axis tight 
grid on;
xlim([0,3])
%your plots
set(gca,'TickLabelInterpreter','Latex')
set(curr_fig,'Units','centimeters','PaperSize',[20.98 29.68],'PaperUnits','centimeters','PaperPosition',[0 0 12 8])
% you can change 9 and 6.3 to change the ratios of the plot...
savefig('figures/pendulum2.fig') %change it with the name you want to give to the .fig plot
print -depsc figures/pendulum2 %change it with the name you want to give to the .eps figure



