try
    handling
catch e
    if typeof(e) == UndefVarError
        println(stderr, "Execute \"RunTests.jl\" instead.")
        exit(1)
    else
        rethrow()
    end
end

using Test

# Escaping

mystery(n) =
    1 +
    to_escape() do outer
        1 +
        to_escape() do inner
            1 +
            if n == 0
                inner(1)
            elseif n == 1
                outer(1)
            else
                1
        end
    end
end

@test mystery(0) == 3
@test mystery(1) == 2
@test mystery(2) == 4


# Handling

@test handling(() -> 123) == 123

struct DivisionByZero <: Exception
end

simple_reciprocal(x) = x == 0 ? error(DivisionByZero()) : 1/x

@test to_escape() do exit
    handling(DivisionByZero => (c) -> exit(true)) do
        simple_reciprocal(0)
    end
end

@test let saw0 = false, saw1 = false
    to_escape() do exit
        handling(DivisionByZero => (c)-> (saw0 = true; exit(true))) do
            handling(DivisionByZero => (c)-> (saw1 = true)) do
                simple_reciprocal(0)
            end
        end
    end
    saw0 && saw1
end


struct LineEndLimit <: Exception
end

function print_line(str, signal_func, line_end=20)
    global text = ""
    let col = 0 
        for c in str
            text *= c
            col += 1
            if col == line_end
                signal_func(LineEndLimit())
                col = 0
            end
        end
    end
    text
end

@test print_line("Hi, everybody! How are you feeling today?", signal) == "Hi, everybody! How are you feeling today?"
@test begin
    to_escape() do exit
        handling(LineEndLimit => (c)->exit()) do
            print_line("Hi, everybody! How are you feeling today?", signal)
        end
    end
    text == "Hi, everybody! How a"
end
@test handling(LineEndLimit => (c) -> global text *= "\n") do
    print_line("Hi, everybody! How are you feeling today?", signal)
end == "Hi, everybody! How a\nre you feeling today\n?"

@test begin
    to_escape() do exit
        handling(LineEndLimit => (c)->exit()) do
            print_line("Hi, everybody! How are you feeling today?", error)
        end
    end
    text == "Hi, everybody! How a"
end
@test_throws LineEndLimit handling(LineEndLimit => (c) -> global text *= "\n") do
    print_line("Hi, everybody! How are you feeling today?", error)
end
@test text == "Hi, everybody! How a\n"


# Restarts

reciprocal(value) =
    with_restart(
        :return_zero => ()->0,
        :return_value => identity,
        :retry_using => reciprocal
    ) do
        value == 0 ?
            error(DivisionByZero()) :
            1/value
    end

@test handling(DivisionByZero => (c)->invoke_restart(:return_zero)) do
    reciprocal(0)
end == 0
@test handling(DivisionByZero => (c)->invoke_restart(:return_value, 123)) do
    reciprocal(0)
end == 123
@test handling(DivisionByZero => (c)->invoke_restart(:retry_using, 10)) do
    reciprocal(0)
end == 0.1
@test_throws UndefinedRestartException handling(DivisionByZero => (c)->invoke_restart(:invalid, 10)) do
    reciprocal(0)
end

@test handling(DivisionByZero =>
    (c) -> for restart in (:return_one, :return_zero, :die_horribly)
        if available_restart(restart)
            invoke_restart(restart)
        end
    end
) do
    reciprocal(0)
end == 0

@test let count = 0
    handling(DivisionByZero => (c) -> (count += 1; invoke_restart(:retry_using, count == 1 ? 0 : 10))) do
        reciprocal(0)
    end == 0.1 && count == 2
end


# From exceptions.pdf, page 20
function print_line_restart(str, signal_func, line_end=20)
    global text = ""
    let col = 0 
        for c in str
            text *= c
            col += 1
            if col == line_end
                restart_result = with_restart(
                    :wrap => () -> (text *= "\n"; col = 0),
                    :truncate => () -> :truncate,
                    :continue => () -> nothing
                ) do
                    signal_func(LineEndLimit())
                end

                if restart_result == :truncate
                    return text
                end
            end
        end
    end
    text
end

@test print_line_restart("Hi, everybody! How are you feeling today?", signal) == "Hi, everybody! How are you feeling today?"
@test begin
    handling(LineEndLimit => (c) -> invoke_restart(:truncate)) do
        print_line_restart("Hi, everybody! How are you feeling today?", signal)
    end
    text == "Hi, everybody! How a"
end
@test handling(LineEndLimit => (c) -> invoke_restart(:wrap)) do
    print_line_restart("Hi, everybody! How are you feeling today?", signal)
end == "Hi, everybody! How a\nre you feeling today\n?"

@test begin
    handling(LineEndLimit => (c) -> invoke_restart(:truncate)) do
        print_line_restart("Hi, everybody! How are you feeling today?", error)
    end
    text == "Hi, everybody! How a"
end
@test handling(LineEndLimit => (c) -> invoke_restart(:wrap)) do
    print_line_restart("Hi, everybody! How are you feeling today?", error)
end == "Hi, everybody! How a\nre you feeling today\n?"


# Nested restarts

function reciprocal_vector(input)
    output = Vector()
    for value in input
        with_restart(:skip => () -> nothing) do
            push!(output, reciprocal(value))
        end
    end
    output
end

@test reciprocal_vector([2, 3]) == [1/2, 1/3]

@test handling(DivisionByZero => (c) -> invoke_restart(:return_zero)) do
    reciprocal_vector([1, 0, 2])
end == [1, 0, 1/2]

@test handling(DivisionByZero => (c) -> invoke_restart(:skip)) do
    reciprocal_vector([1, 0, 2])
end == [1, 1/2]
