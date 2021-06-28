-module(remoteMultiThreadServer).
-define(Puerto, 1234).
-export([start/0,fin/1,receptor/1,echoResp/2, clientStart/1]).
-export([nicknameserverinit/0]).

%% start: Crear un socket, y ponerse a escuchar.
start()->
    %% register(servidor, self()),
    {ok, Socket} = gen_tcp:listen(?Puerto, [ list, {active, false}]),
    register(servidorNicknames, spawn(?MODULE, nicknameserverinit, [])),
    spawn(?MODULE,receptor, [Socket]),
    Socket .

fin(Socket) ->
    gen_tcp:close(Socket),
    ok.

%% receptor: Espera a los clientes y crea nuevos actores para atender los pedidos.
%%
receptor(Socket) ->
    %% receive
    %%     fin -> gen_tcp:close(Socket), ok
    %% after 0 ->
    case gen_tcp:accept(Socket) of
        {ok, CSocket}  ->
            spawn(?MODULE, clientStart,[CSocket]);
        {error, closed} ->
            io:format("Se cerró el closed, nos vamos a mimir"),
            broadcast(Socket, "/server closed"),
            exit(normal);
        {error, Reason} ->
            io:format("Falló la espera del client por: ~p~n",[Reason])
    end,
    receptor(Socket).
    %% end.

clientStart(Socket) ->
    case createUser(Socket) of
        {ok, MyNickname} -> 
            broadcast(Socket, MyNickname ++ " ENTRO A LA SALA"),
            gen_tcp:send(Socket, "BENVINDO\0"),
            echoResp(Socket, MyNickname);
        error -> 
            io:format("El cliente cerró la conexión~n")
    end.

%% echoResp: atiende al cliente.
%%
echoResp(Socket, MyNickname) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, "/exit"} -> 
            io:format("Me llegó ~s ~n",["/exit"]),
            broadcast(Socket, MyNickname ++ " SE FUE DE LA SALA"),
            servidorNicknames ! {deleteUser, Socket, self()},
            receive
                ok -> gen_tcp:close(Socket)
            end,
            ok;
        {ok, "/nickname " ++ Paquete} ->
            [Nickname, _] = string:split(Paquete,[0]),
            io:format("Me llegó ~s ~n",["/nickname " ++ Nickname]),
            case nicknameValidation(string:trim(Nickname)) of
                {0, 0} -> 
                    servidorNicknames ! {cambiarNickname, string:trim(Nickname), Socket, self()},
                    receive
                        {ok, NewNickname} -> 
                            broadcast(Socket, MyNickname ++ " CAMBIO SU NICKNAME A " ++ NewNickname),
                            gen_tcp:send(Socket, "NICKNAME ACTUALIZADO\0"),
                            echoResp(Socket, NewNickname);
                        error ->
                            gen_tcp:send(Socket, "NICKNAME YA EN USO\0"),
                            echoResp(Socket, MyNickname)
                    end;
                _ ->
                    gen_tcp:send(Socket, "NICKNAME INVALIDO\0"),
                    echoResp(Socket, MyNickname)
            end;
        {ok, "/msg " ++ Paquete} ->
            [Msg, _] = string:split(Paquete,[0]),
            io:format("Me llegó ~s ~n",["/msg " ++ Msg]),
            case splitFirstSpace(Msg) of
                {ok, Nickname, Msg2} -> 
                    servidorNicknames ! {buscarNickname, Nickname, self()},
                    receive
                        {ok, SocketUsuario} ->
                            gen_tcp:send(SocketUsuario, MyNickname ++ " TE SUSURRO " ++ Msg2 ++ "\0"),
                            echoResp(Socket, MyNickname);
                        error -> 
                            gen_tcp:send(Socket, "NICKNAME NO ENCONTRADO\0"),
                            echoResp(Socket, MyNickname)
                    end;
                error -> 
                    gen_tcp:send(Socket, "FORMATO INVALIDO\0"),
                    echoResp(Socket, MyNickname)
            end;
        {ok, "/" ++ Paquete} ->
            [Msg, _] = string:split(Paquete,[0]),
            io:format("Me llegó ~s ~n",["/" ++ Msg]),
            gen_tcp:send(Socket, "COMANDO INVALIDO\0"),
            echoResp(Socket, MyNickname);
        {ok, Paquete} ->
            [Msg, _] = string:split(Paquete,[0]),
            io:format("Me llegó ~s ~n",[Msg]),
            broadcast(Socket, MyNickname ++ ": " ++ Msg),
            echoResp(Socket, MyNickname);
        {error, closed} ->
            io:format("El cliente cerró la conexión~n"),
            broadcast(Socket, MyNickname ++ " SE FUE DE LA SALA"),
            servidorNicknames ! {deleteUser, Socket, self()}
    end.

broadcast(Socket, Msg) ->
    servidorNicknames ! {verLista, self()},
    receive
        {ok, Lista} ->
            lists:foreach( 
                fun ({_, SocketUser}) -> 
                    if
                        SocketUser /= Socket -> 
                            gen_tcp:send(SocketUser, Msg ++ "\0");
                        true ->
                            ok
                    end
                end, Lista)
    end.

createUser(Socket) ->
    gen_tcp:send(Socket, "INGRESE UN NICKNAME:\0"),
    case gen_tcp:recv(Socket, 0) of
        {ok, "/exit"} -> 
            io:format("Me llegó ~s ~n",["/exit"]),
            gen_tcp:close(Socket),
            error;
        {ok, Paquete} ->
            [Nickname, _] = string:split(Paquete,[0]),
            io:format("Me llegó ~s ~n",[Nickname]),
            case nicknameValidation(Nickname) of
                {0, 0} -> 
                    servidorNicknames ! {nuevoNickname, Nickname, Socket, self()},
                    receive
                        ok -> {ok, Nickname};
                        error ->
                            gen_tcp:send(Socket, "NICKNAME YA EN USO\0"),
                            createUser(Socket)
                    end;
                _ ->
                    gen_tcp:send(Socket, "NICKNAME INVALIDO\0"),
                    createUser(Socket)
            end
    end.

splitFirstSpace(Msg) ->
    case string:split(Msg, " ") of
        [Nickname, Msg2] -> {ok, Nickname, Msg2};
        _ -> error
    end.

%%%%%%%%%%% Servidor
%% Función de servidor de nombres.
nicknameserverinit() ->
    servnicknames([]).

servnicknames(List) ->
    receive
        {nuevoNickname, Nickname, Socket, CId} ->
            case nicknameListIsPresentNickname(List, Nickname) of
                false -> 
                    CId ! ok,
                    servnicknames([{Nickname, Socket}] ++ List);
                _ ->
                    CId ! error,
                    servnicknames(List)
            end;
        {cambiarNickname, Nickname, Socket, CId} ->
            case nicknameListIsPresentNickname(List, Nickname) of
                false -> 
                    CId ! {ok, Nickname},
                    servnicknames(nicknameListChangeNickname(List, Nickname, Socket));
                _ ->
                    CId ! error,
                    servnicknames(List)
            end;
        {deleteUser, Socket, CId} ->
            CId ! ok,
            servnicknames(nicknameListDelete(List, Socket));
        {buscarNickname, Nickname, CId} ->
            case nicknameListFindNickname(List, Nickname) of
                {ok, Socket} -> CId ! {ok, Socket};
                error -> CId ! error
            end,
            servnicknames(List);
        {verLista, CId} ->
            CId ! {ok, List},
            servnicknames(List);
        _ -> io:format("DBG: otras cosas~n"),
             servnicknames(List)
    end.

nicknameListDelete([{SavedNickname, SavedSocket}|Tl], Socket) ->
    if
    SavedSocket == Socket ->
        Tl;
    true ->
        [{SavedNickname, SavedSocket}] ++ nicknameListDelete(Tl, Socket)
    end.

nicknameListChangeNickname([{SavedNickname, SavedSocket}|Tl], Nickname, Socket) ->
    if
    SavedSocket == Socket ->
        [{Nickname, Socket}|Tl];
    true ->
        [{SavedNickname, SavedSocket}] ++ nicknameListChangeNickname(Tl, Nickname, Socket)
    end.

nicknameListIsPresentNickname([], _) ->
    false;
nicknameListIsPresentNickname([{SavedNickname, _}|Tl], Nickname) ->
    if
    SavedNickname == Nickname ->
        true;
    true ->
        nicknameListIsPresentNickname(Tl, Nickname)
    end.

nicknameListFindNickname([], _) ->
    error;
nicknameListFindNickname([{SavedNickname, Socket}|Tl], Nickname) ->
    if
    SavedNickname == Nickname ->
        {ok, Socket};
    true ->
        nicknameListFindNickname(Tl, Nickname)
    end.

nicknameValidation(Nickname) ->
    {string:str(Nickname, " "), string:str(Nickname, "/")}.