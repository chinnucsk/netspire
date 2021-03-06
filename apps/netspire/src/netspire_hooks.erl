-module(netspire_hooks).

%% API
-export([add/3, add/4, delete/3, delete/4, delete_all/1,
         run/2, run_fold/3]).

-include("netspire.hrl").

add(Hook, Module, Fun) ->
    add(Hook, Module, Fun, 100).
add(Hook, Module, Fun, Seq) ->
    case ets:lookup(netspire_hooks, Hook) of
        [{_, Ls}] ->
            El = {Seq, Module, Fun},
            case lists:member(El, Ls) of
                true ->
                    ok;
                false ->
                    NewLs = lists:merge(Ls, [El]),
                    ets:insert(netspire_hooks, {Hook, NewLs})
            end;
        [] ->
            NewLs = [{Seq, Module, Fun}],
            ets:insert(netspire_hooks, {Hook, NewLs})
    end.

delete(Hook, Module, Fun) ->
    delete(Hook, Module, Fun, 100).
delete(Hook, Module, Fun, Seq) ->
    case ets:lookup(netspire_hooks, Hook) of
        [{_, Ls}] ->
            NewLs = lists:delete({Seq, Module, Fun}, Ls),
            ets:insert(netspire_hooks, {Hook, NewLs});
        [] ->
            ok
    end.

delete_all(Module) ->
    do_delete_all(ets:first(netspire_hooks), Module).

run(Hook, Args) ->
    case ets:lookup(netspire_hooks, Hook) of
        [{_, Ls}] ->
            do_run(Ls, Hook, Args);
        [] ->
            ok
    end.

run_fold(Hook, Val, Args) ->
    case ets:lookup(netspire_hooks, Hook) of
        [{_, Ls}] ->
            do_run_fold(Ls, Hook, Val, Args);
        [] ->
            Val
    end.


%%
%% Internal API
%%
do_run([], _Hook, _Args) -> ok;
do_run([{_Seq, Module, Fun} | Ls], Hook, Args) ->
    try apply(Module, Fun, Args) of
        stop ->
            ok;
        _ ->
            do_run(Ls, Hook, Args)
    catch
        _:Reason ->
            ?ERROR_MSG("Error while running hook ~p ~p"
                       " with args: ~p due to ~p~n", [Hook, {Module, Fun}, Args, Reason]),
            do_run(Ls, Hook, Args)
    end.

do_run_fold([], _Hook, Value, _Args) -> Value;
do_run_fold([{_Seq, Module, Fun} | Ls], Hook, Value, Args) ->
    try apply(Module, Fun, [Value | Args]) of
        stop ->
            stop;
        {stop, NewValue} ->
            NewValue;
        NewValue ->
            do_run_fold(Ls, Hook, NewValue, Args)
    catch
        _:Reason ->
            ?ERROR_MSG("Error while running hook ~p ~p"
                       " with args: ~p due to ~p~n", [Hook, {Module, Fun}, Args, Reason]),
            do_run_fold(Ls, Hook, Value, Args)
    end.

do_delete_all('$end_of_table', _Module) -> ok;
do_delete_all(Hook, Module) ->
    case ets:lookup(netspire_hooks, Hook) of
        [{_, Ls}] ->
            NewLs = [{_Seq, M, _Fun} || {_Seq, M, _Fun} <- Ls, M =/= Module],
            ets:insert(netspire_hooks, {Hook, NewLs});
        [] -> ok
    end,
    Next = ets:next(netspire_hooks, Hook),
    do_delete_all(Next, Module).
