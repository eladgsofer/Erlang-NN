-module(cortex).
-compile([debug_info]).
-compile(export_all).
-include("records.hrl").
-include("config.hrl").

gen(PhenoTypePid,Node)-> spawn(Node,?MODULE,loop,[PhenoTypePid]).

loop(ExoSelf_PId) ->
	receive
		{ExoSelf_PId,{Id,SPIds,APIds,NPIds}, TotSteps} ->
			put(start_time,now()),
			Init_loc=?HUNTER_INIT_LOC,
			[RabbitFLoc|_] = exoself:generateRabbitPatrol(),
			FirstSimStep = RabbitFLoc ++ Init_loc,
			[SPId ! {self(),sync,Init_loc} || SPId <- SPIds],
			loop(Id,ExoSelf_PId,SPIds,{APIds,APIds},NPIds,TotSteps, {Init_loc, 0, [FirstSimStep]})
	end.
%The gen/2 function spawns the cortex element, which immediately starts to wait for a the state message from the same process that spawned it, exoself. The initial state message contains the sensor, actuator, and neuron PId lists. The message also specifies how many total Sense-Think-Act cycles the Cortex should execute before terminating the NN system. Once we implement the learning algorithm, the termination criteria will depend on the fitness of the NN, or some other useful property

% Terminating the network when simulation is over - backing up the current status
loop(Id,ExoSelf_PId,SPIds,{_APIds,MAPIds},NPIds,0, {HunterLoc, DistanceAcc, SimulationStepsAcc}) ->
	TimeDif = timer:now_diff(now(),get(start_time)),
	%io:format("Cortex:~p is backing up and terminating.~n",[Id]),
	%io:format("Operational time:~p~n",[TimeDif]),
	Neuron_IdsNWeights = get_backup(NPIds,[]),
	Fitness_Score = math:sqrt(DistanceAcc), % Euclead Norm
	SimStepsVec = lists:reverse(SimulationStepsAcc),
	% backup the network in a file
	ExoSelf_PId ! {self(),score_and_backup, {Neuron_IdsNWeights, Fitness_Score, SimStepsVec}},
	% Terminating all the network
	[PId ! {self(),terminate} || PId <- SPIds],
	[PId ! {self(),terminate} || PId <- MAPIds],
	[PId ! {self(),termiante} || PId <- NPIds];

loop(Id,ExoSelf_PId,SPIds,{[APId|APIds],MAPIds},NPIds,Step, {_, DistanceAcc, SimulationStepsAcc}) ->
	receive
		{APId,sync,HunterLoc} ->
			{CurrDist, SimStep} = calcDistance(Step, HunterLoc),
			loop(Id,ExoSelf_PId,SPIds,{APIds,MAPIds},NPIds,Step,{HunterLoc, CurrDist+DistanceAcc, [SimStep|SimulationStepsAcc]});
		terminate ->
			io:format("Cortex:~p is terminating.~n",[Id]),
			[PId ! {self(),terminate} || PId <- SPIds],
			[PId ! {self(),terminate} || PId <- MAPIds],
			[PId ! {self(),termiante} || PId <- NPIds]
	end;
loop(Id,ExoSelf_PId,SPIds,{[],MAPIds},NPIds,Step, {Hunter_loc, DistanceAcc, SimulationStepsAcc})->

	[PId ! {self(),sync,Hunter_loc} || PId <- SPIds],
	loop(Id,ExoSelf_PId,SPIds,{MAPIds,MAPIds},NPIds,Step-1,{Hunter_loc, DistanceAcc, SimulationStepsAcc}).
%The cortex's goal is to synchronize the the NN system such that when the actuators have received all their control signals, the sensors are once again triggered to gather new sensory information. Thus the cortex waits for the sync messages from the actuator PIds in its system, and once it has received all the sync messages, it triggers the sensors and then drops back to waiting for a new set of sync messages. The cortex stores 2 copies of the actuator PIds: the APIds, and the MemoryAPIds (MAPIds). Once all the actuators have sent it the sync messages, it can restore the APIds list from the MAPIds. Finally, there is also the Step variable which decrements every time a full cycle of Sense-Think-Act completes, once this reaches 0, the NN system begins its termination and backup process.

get_backup([NPId|NPIds],Acc)->
	NPId ! {self(),get_backup},
	receive
		{NPId,NId,WeightTuples}-> get_backup(NPIds,[{NId,WeightTuples}|Acc])
	end;
get_backup([],Acc)-> Acc.

%During backup, cortex contacts all the neurons in its NN and requests for the neuron's Ids and their Input_IdPs. Once the updated Input_IdPs from all the neurons have been accumulated, the list is sent to exoself for the actual backup and storage.
calcDistance(Step, HunterLoc)->
	Actual_Step = ?SIM_ITERATIONS - Step,
	% Calc The rabbit coordinates
	%TODO extract from --records..
	RabbitVec = lists:seq(1,?SIM_ITERATIONS),

	RabbitLoc = lists:nth(Actual_Step, RabbitVec),
	[R_X, R_Y, H_X, H_Y] = [RabbitLoc, RabbitLoc] ++ HunterLoc,
	
	Distance = math:pow(R_X-H_X,2) + math:pow(R_Y-H_Y,2),
	%io:format("STEP:~p DISTANCE:~p~n", [Actual_Step, Distance]),
	{Distance, [R_X, R_Y, H_X, H_Y]}.
