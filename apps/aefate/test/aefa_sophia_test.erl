%%%-------------------------------------------------------------------
%%% @copyright (C) 2019, Aeternity Anstalt
%%% @doc Basic tests Sophia-to-Fate pipeline
%%% @end
%%%-------------------------------------------------------------------
-module(aefa_sophia_test).

-compile([export_all, nowarn_export_all]).

-include_lib("eunit/include/eunit.hrl").

%% -- Compiling and running --

compile_and_run(Contracts, Contract, Function, Arguments) ->
    Chain = compile_contracts(Contracts),
    run(Chain, Contract, Function, Arguments).

compile_contracts(Contracts) ->
    setup_chain(maps:from_list([ {Name, compile_contract(Code)} || {Name, Code} <- Contracts ])).

run(Chain, Contract, Function, Arguments) ->
    aefa_fate:run(make_call(Contract, Function, Arguments), Chain).

expect(Chain, Contract, Function, Arguments, Expect) ->
    {ok, #{ accumulator := Result,
            trace       := Trace }} = run(Chain, Contract, Function, Arguments),
    ?assertMatch({Expect, _}, {Result, Trace}).

%% For now, implement pipeline here.
compile_contract(Code) ->
    compile_contract(Code, [{debug, [scode, opt, opt_rules, compile]}]).

compile_contract(Code, Options) ->
    {ok, Ast} = aeso_parser:string(Code),
    TypedAst  = aeso_ast_infer_types:infer(Ast, Options),
    FCode     = aeso_ast_to_fcode:ast_to_fcode(TypedAst, Options),
    aeso_fcode_to_fate:compile(FCode, Options).

setup_chain(Contracts) ->
    #{ contracts => Contracts }.

make_call(Contract, Function, Arguments) ->
    EncArgs  = list_to_tuple([aeb_fate_data:encode(A) || A <- Arguments]),
    Calldata = {tuple, {Function, {tuple, EncArgs}}},
    #{ contract => Contract,
       call => aeb_fate_encoding:serialize(Calldata) }.

mk_test(Contracts, Tests) ->
    Main  = element(1, hd(Contracts)),
    Chain = compile_contracts(Contracts),
    Pr    = fun(X) -> io_lib:format("~p", [X]) end,
    [{lists:flatten(io_lib:format("~s(~s) -> ~p", [Fun, string:join(lists:map(Pr, Args), ", "), Res])),
      fun() -> expect(Chain, Main, list_to_binary(Fun), Args, Res) end}
    || {Fun, Args, Res} <- Tests ].

run_eunit(Test) ->
    [ begin io:format("~s\n", [Name]), Fun() end || {Name, Fun} <- ?MODULE:Test() ],
    ok.

%% -- Actual tests --

arithmetic() ->
    {<<"arithmetic">>,
     "contract Arith =\n"
     "  function id    (x : int) = x\n"
     "  function inc   (x : int) = x + 1\n"
     "  function inc'  (x : int) = 1 + x\n"
     "  function plus2 (x : int) = x + 2\n"
     "  function plus4 (x : int) = x + 2 + 2\n"
     "  function plus4'(x : int) = x + (2 + 2)\n"
     "  function dec   (x : int) = x - 1\n"
     "  function sub2  (x : int) = x - 2\n"
     "  function eq0   (x : int) = x == 0\n"
     "  function eq3   (x : int) = x == 3\n"
     "  function pred  (x : int) = if (x == 0) 0 else x - 1\n"
     "  function iadd  (x, y)    = (x + y) + 3\n"
     "  function nest  (x : int, y : int) =\n"
     "    if   (x == 0) 0\n"
     "    elif (y == 0) x + 1\n"
     "    else x + y\n"
     "  function local (x : int) =\n"
     "    let y = x + 1\n"
     "    y + y\n"
    }.

arith_tests() ->
    Nest = fun(0, _) -> 0; (X, 0) -> X + 1; (X, Y) -> X + Y end,
    [ {"id",     [142],  142}
    , {"inc",    [142],  143}
    , {"inc'",   [142],  143}
    , {"plus2",  [142],  144}
    , {"plus4",  [142],  146}
    , {"plus4'", [142],  146}
    , {"dec",    [0],     -1}
    , {"dec",    [14],    13}
    , {"sub2",   [20],    18}
    , {"local",  [20],    42} ] ++
    [ {"eq0",  [X], X == 0} || X <- [0, 99] ] ++
    [ {"eq3",  [X], X == 3} || X <- [3, -100] ] ++
    [ {"pred", [X], max(0, X - 1)} || X <- [0, 100] ] ++
    [ {"nest", [X, Y], Nest(X, Y)} || X <- [0, 10], Y <- [0, -99] ] ++
    [].

arith_test_() -> mk_test([arithmetic()], arith_tests()).

tuples() ->
    {<<"tuples">>,
     "contract Tuples =\n"
     "  function fst(p : (int, string)) =\n"
     "    switch(p)\n"
     "      (x, y) => x\n"
     "  function fst'(p : (int, string)) =\n"
     "    switch(p)\n"
     "      (x, _) => x\n"
     "  function snd(p : (int, string)) =\n"
     "    switch(p)\n"
     "      (x, y) => y\n"
     "  function snd'(p : (int, string)) =\n"
     "    switch(p)\n"
     "      (_, y) => y\n"
     "  function sum(p) =\n"
     "    switch(p)\n"
     "      (x, y) => x + y\n"
     "  function swap(p : (int, string)) =\n"
     "    switch(p)\n"
     "      (x, y) => (y, x)\n"
     "  function id(p : (int, int, string)) =\n"
     "    switch(p)\n"
     "      (x, y, z) => (x, y, z)\n"
     "  function nest(p : ((int, int), string)) =\n"
     "    switch(p)\n"
     "      (xy, z) => switch(xy) (x, y) => (x, y, z)\n"
    "  function deep(p : ((int, int), (int, int))) =\n"
    "    switch(p)\n"
    "      ((x, y), (z, w)) => (x, y, z, w)\n"
    "  function deep_sum(p : ((int, int), (int, int))) =\n"
    "    switch(p)\n"
    "      ((x, y), (z, w)) => x + y + z + w\n"
    }.

tuple_tests() ->
    A    = 42,
    B    = 199,
    S    = <<"forty-two">>,
    lists:flatten(
    [ [],
      [{Fst, [{A, S}], A} || Fst <- ["fst", "fst"]],
      [{Snd, [{A, S}], S} || Snd <- ["snd", "snd'"]],
      [{"sum",  [{A, B}], A + B}],
      [{"swap", [{A, S}], {tuple, {S, A}}}],
      [{"id",   [{A, B, S}],   {tuple, {A, B, S}}}],
      [{"nest", [{{A, B}, S}], {tuple, {A, B, S}}}],
      [{"deep", [{{A, B}, {A + 1, B + 1}}], {tuple, {A, B, A + 1, B + 1}}}],
      []
    ]).

tuple_test_() -> mk_test([tuples()], tuple_tests()).

patterns() ->
    {<<"patterns">>,
     "contract PatternMatching =\n"
     "  function or(p : (bool, bool)) =\n"
     "    switch(p)\n"
     "      (false, y) => y\n"
     "      (true,  _) => true\n"
     "  function and'(p : (bool, bool)) =\n"
     "    switch(p)\n"
     "      (x, false) => false\n"
     "      (x, true)  => x\n"
     ""}.

pattern_tests() ->
    lists:flatten(
      [ [],
        [{"or",   [{A, B}], A or  B} || A <- [false, true], B <- [false, true]],
        [{"and'", [{A, B}], A and B} || A <- [false, true], B <- [false, true]],
        []
      ]).

pattern_test_() -> mk_test([patterns()], pattern_tests()).

