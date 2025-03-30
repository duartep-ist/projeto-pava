module ExceptionalExtended

struct Restart
    name::Symbol
    func::Function
    test::Function
    report::Function
    interactive::Function
end

struct RestartInfo
    handler_dict::Dict{Symbol, Restart}
    escape::Function
    caller::Function
end

struct ExceptionHandler
    exception::DataType
    handler::Function
end

exception_handlers::Vector{Vector{ExceptionHandler}} = []
restart_stack::Vector{RestartInfo} = []

function handling(func, handlers...)
    let handler_list = [ExceptionHandler(h.first, h.second) for h in handlers]
        push!(exception_handlers, handler_list)
        try
            func()
        finally
            pop!(exception_handlers)
        end
    end
end

struct EscapedException <: Exception end
escaped = EscapedException()

function to_escape(func)
    let did_escape = false, ret_val = nothing
        escape(ret::Any) = begin did_escape = true; ret_val = ret; throw(escaped) end
        escape() = escape(nothing)

        try
            func(escape)
        catch
            if did_escape
                return ret_val
            else
                rethrow()
            end
        end
    end
end


function parse_restart(restart)
    let name = restart.first, func = nothing, test = () -> true, report = () -> (uppercase(String(restart.first))), interactive = () -> ()
        if restart.second isa Tuple # (:name, (:report, report, :interactive, interactive, :test, test))
            func = restart.second[1]
            for i in 2:length(restart.second)
                if restart.second[i] == :test
                    test = restart.second[i+1]
                elseif restart.second[i] == :report
                    report = restart.second[i+1]
                elseif restart.second[i] == :interactive
                    interactive = restart.second[i+1]
                end
                i = i+1
            end
        else # (:name, func)
            func = restart.second
        end
        return Restart(name, func, test, report, interactive)
    end
end

function print_restarts(exception)
    let restarts::Vector{Pair{Function, Restart}} = [], chosen::Union{Nothing, Pair{Function, Restart}} = nothing
    println("Error of type: $exception")
    println("Available restarts:")
    for info in Iterators.reverse(restart_stack)
        for r in values(info.handler_dict)
            if r.test()
                push!(restarts, Pair(info.escape, r))
                println("$(length(restarts)): [$(uppercase(String(r.name)))] $(r.report())")
            end
        end
    end

    # Retry
    push!(restarts, restart_stack[end].escape => parse_restart(:retry => restart_stack[end].caller))
    println("$(length(restarts)): [RETRY] Retry evaluation request.")

    # Abort
    push!(restarts, restart_stack[begin].escape => parse_restart(:abort => () -> (throw(exception))))
    println("$(length(restarts)): [ABORT] Abort entirely from this Julia process.")

    print("Choose one restart: ")
    chosen = restarts[parse(Int, readline())]

    chosen.first(chosen.second.func(chosen.second.interactive()...))
    end
end

function with_restart(func, restarts...)
    let restart_handler_dict = Dict([(r.first => parse_restart(r)) for r in restarts])
        try
            to_escape() do escape
                push!(restart_stack, RestartInfo(restart_handler_dict, escape, func))
                func()
            end
        finally
            pop!(restart_stack)
        end
    end
end

function available_restart(name)
    for info in Iterators.reverse(restart_stack)
        if name in keys(info.handler_dict) && info.handler_dict[name].test()
            return true
        end
    end
    false
end

function invoke_restart(name, args...)
    for info in Iterators.reverse(restart_stack)
        if name in keys(info.handler_dict) && info.handler_dict[name].test()
            info.escape(info.handler_dict[name].func(args...))
            return
        end
    end
    throw(UnavailableRestartException(name))
end

function signal(exception::Exception)
    for handler_frame in reverse(exception_handlers)
        for handler in handler_frame
            if exception isa handler.exception
                handler.handler(exception)
                break
            end
        end
    end    
end


function Base.error(exception::Exception)
    signal(exception)
    if length(restart_stack) > 0
        print_restarts(exception)
    end
    throw(exception)
end


# Macros

function verify_single_param_list(ex)
    if !(typeof(ex) == Symbol || (typeof(ex) == Expr && ex.head == :tuple && length(ex.args) <= 1))
        error("expected zero or one parameter names")
    end
end
function bare_identifier_to_tuple(ex)
    if typeof(ex) == Symbol
        :(($ex,))
    elseif typeof(ex) == Expr && ex.head == :tuple
        ex
    else
        error("expected an identifier or a tuple of identifiers")
    end
end

struct HandlerCaseResult
    index::Int16
    exception::Exception
end
macro handler_case(ex, cases...)
    for case in cases
        verify_single_param_list(case.args[2])
    end
    error_cases = filter((case) -> case.args[1] != :nothing, cases)
    no_error_cases = filter((case) -> case.args[1] == :nothing, cases)
    if length(no_error_cases) > 1
        error("no more than 1 no error case can be present.")
    end
    no_error_case = length(no_error_cases) != 0 ? no_error_cases[1] : nothing

    :(
        let output,
            result = to_escape() do exit
                handling($(
                    [:(
                        $(esc(error_cases[i].args[1])) => exception -> exit(HandlerCaseResult($i, exception))
                    ) for i in 1:length(error_cases)]...
                )) do
                    $(esc(ex))
                end
            end

            if typeof(result) == HandlerCaseResult
                $([:(
                    if result.index == $i
                        output = let $(esc(error_cases[i].args[2])) = result.exception
                            $(esc(error_cases[i].args[3]))
                        end
                    end
                ) for i in 1:length(error_cases)]...)
            else
                output = $(
                    no_error_case == nothing ?
                        :result :
                        :(
                            let $(esc(no_error_case.args[2])) = result
                                $(esc(no_error_case.args[3]))
                            end
                        )
                )
            end

            output
        end
    )
end


struct RestartCaseResult
    index::Int16
    args::Tuple
end
struct RestartCaseParsedCase
    name::Symbol
    params::Expr
    body::Any

    options::Dict{Symbol, Any}
end
const valid_restart_options = [:test, :report, :interactive]
function parse_restart_case_option(element)
    if typeof(element.args[1]) != Symbol
        error("invalid restart option name \"$(element.args[1])\" in restart case")
    end
    if !(element.args[1] in valid_restart_options)
        error("unknown restart option \"$(element.args[1])\"")
    end

    element.args[1] => element.args[2]
end
macro restart_case(ex, cases...)
    parsed_cases = map(case -> let positional_args = filter(arg -> !(typeof(arg) == Expr && arg.head == :(=)), case.args),
                                   optional_args = filter(arg -> typeof(arg) == Expr && arg.head == :(=), case.args),
                                   options = Dict([parse_restart_case_option(arg) for arg in optional_args])

        RestartCaseParsedCase(
            positional_args[1],
            bare_identifier_to_tuple(case.args[2]),
            positional_args[3],
            options
        )
    end, cases)

    :(
        let output,
            result = to_escape() do exit
                with_restart($(
                    [:(
                        # QuoteNode is used to transform the identifier into a symbol
                        $(QuoteNode(parsed_cases[i].name)) => (
                            # The first member of the tuple is the restart callback
                            $(esc(parsed_cases[i].params)) -> exit(RestartCaseResult($i, $( esc(parsed_cases[i].params) ))),
                            # The rest of the members are the options
                            $(Iterators.flatten([
                                # Each option is represented by 2 consecutive members, one for the name and another for the value
                                [QuoteNode(name), esc(value)]
                            for (name, value) in parsed_cases[i].options])...)
                        )
                    ) for i in 1:length(parsed_cases)]...
                )) do
                    $(esc(ex))
                end
            end

            if typeof(result) == RestartCaseResult
                $([:(
                    if result.index == $i
                        # This relies on destructuring
                        output = let $(esc(parsed_cases[i].params)) = result.args
                            $(esc(parsed_cases[i].body))
                        end
                    end
                ) for i in 1:length(parsed_cases)]...)
            else
                output = result
            end

            output
        end
    )
end


# Library errors

struct UnavailableRestartException <: Exception
    name::Symbol
end
function Base.showerror(io::IO, e::UnavailableRestartException)
    print(io, "UnavailableRestartException: the restart named \"$(e.name)\" is not available.")
end


# Example
struct DivisionByZero <: Exception end

divide(a, b) = with_restart(:return_zero => (() -> 0, :test, () -> false),
                            :return_value => (identity, :interactive, ()->(let ret::String
                                                                               print("Enter a return value: ")
                                                                               ret = readline()
                                                                               ret
                                                                           end)),
                            :retry_using => (divide, :report, ()->"Retry using another numerator and denominator",
                                                     :interactive, ()->(let a::Int, b::Int
                                                                            print("Enter a numerator: ")
                                                                            a = parse(Int, readline())
                                                                            print("Enter a denominator: ")
                                                                            b = parse(Int, readline())
                                                                            a,b
                                                                        end))) do
                            b == 0 ? 
                            error(DivisionByZero()) :
                            a/b
end

export to_escape, handling, with_restart, available_restart, invoke_restart, signal, @handler_case, @restart_case, divide, UnavailableRestartException, DivisionByZero
end
