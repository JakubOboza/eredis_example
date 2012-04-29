-module(eredis_example).
-behaviour(gen_server).

-author("jakub.oboza@gmail.com").
-define(Prefix, "eredis_example").

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, terminate/2, handle_info/2, code_change/3, stop/1]).
-export([get_user_by_id/1, get_user_id_by_name/1, save_user/1]).

% record description

-record(user, {id = nil, name, password_hash}).

% public api

start_link(_Args) ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
  {ok, Redis} = eredis:start_link(),
  {ok, Redis}.

stop(_Pid) ->
  stop().

stop() ->
    gen_server:cast(?MODULE, stop).

%% public client api

get_user_by_id(Id) ->
  gen_server:call(?MODULE, {get_user_id, Id}).

get_user_id_by_name(Name) ->
  gen_server:call(?MODULE, {get_user_id_by_name, Name}).

save_user(User) ->
  case User#user.id of
    nil -> gen_server:call(?MODULE, {create_user, User}) ;
    _   -> gen_server:call(?MODULE, {update_user, User})
  end.


%% genserver handles

handle_call({get_user_id, Id}, _From, Redis) ->
  {ok, Name }   = eredis:q(Redis, ["GET", generate_key(["user", Id, "name"]) ]),
  {ok, PasswordHash }  = eredis:q(Redis, ["GET", generate_key(["user", Id, "password_hash"]) ]),
  User = #user{id = Id, name = binary_to_list(Name), password_hash = binary_to_list(PasswordHash)},
  {reply, {ok, User}, Redis };

handle_call({get_user_id_by_name, Name}, _Form, Redis) ->
  {ok, Id} = eredis:q(Redis, ["GET", generate_key(["user", Name, "id" ]) ]),
  {reply, binary_to_list(Id), Redis};

% this will be little bit unsafe ;) performance over matter!
handle_call({create_user, User}, _From, Redis) ->
  {ok, BId} = eredis:q(Redis, ["INCR", generate_key(["usersNextId"]) ]),  
  Id = binary_to_list(BId),
  Response = eredis:q(Redis, ["SET", generate_key(["user", User#user.name, "id"]), Id ] ), 
  eredis:q(Redis, ["SET", generate_key(["user", Id, "name"]), User#user.name ]),
  eredis:q(Redis, ["SET", generate_key(["user", Id, "password_hash"]), User#user.password_hash ]),
  {reply, Response, Redis};

handle_call({update_user, User}, _From, Redis) ->
  Id = User#user.id,
  eredis:q(Redis, ["SET", generate_key(["user", Id, "name"]), User#user.name ]),
  Response = eredis:q(Redis, ["SET", generate_key(["user", Id, "password_hash"]), User#user.password_hash ]),
  {reply, Response, Redis};

handle_call(_Message, _From, Redis) ->
  {reply, error, Redis}.

handle_cast(_Message, Redis) -> {noreply, Redis}.
handle_info(_Message, Redis) -> {noreply, Redis}.
terminate(_Reason, _Redis) -> ok.
code_change(_OldVersion, Redis, _Extra) -> {ok, Redis}.

generate_key(KeysList) ->
  lists:foldl(fun(Key, Acc) -> Acc ++ ":" ++ Key end, ?Prefix, KeysList).

% tests

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.


-ifdef(TEST).

generate_key_test() ->
  Key = generate_key(["one", "two", "three"]),
  ?assertEqual("eredis_example:one:two:three", Key).

server_test_() ->
  {setup, fun() -> eredis_example:start_link([]) end,
   fun(_Pid) -> eredis_example:stop(_Pid) end,
   fun generate_eredis_example_tests/1}.

generate_eredis_example_tests(_Pid) ->
  [
    ?_assertEqual({ok,<<"OK">>}, eredis_example:save_user( #user{id = "666", name = "jakub", password_hash = "test" } ) ),
    ?_assertEqual({ok, #user{ id = "666", name = "jakub", password_hash = "test"} }, eredis_example:get_user_by_id( "666" ) ),
    ?_assertEqual({ok, <<"OK">>}, eredis_example:save_user( #user{name="kuba", password_hash = "test"} ) )
  ].

-endif.