try
    @macroexpand @handler_case(nothing)
catch e
    if typeof(e) == UndefVarError
        println(stderr, "Execute \"RunTestsExtended.jl\" instead.")
        exit(1)
    else
        rethrow()
    end
end

using Test

square_root(value) =
    with_restart(
        :return_zero => () -> 0,
        :return_value => identity,
        :retry_using => square_root
    ) do
        !isa(value, Real) ?
            error(TypeError(:square_root, "", Real, value)) :
            value < 0 ?
                error(DomainError(value)) :
                sqrt(value)
    end


# The handler_case macro

# For convenience, we implement a @handler_case macro inspired by Common Lisp's handler-case. The
# first argument to @handler_case is the expression to be evaluated. The rest of the arguments are
# tuples containing the exception type, the parameter name, and the expression to be evaluated when
# that exception occurs.

# @handler_case returns the value of the first expression if there were no exceptional situations.
@test @handler_case(
    square_root(4),
    (DomainError, (), "Domain error!"),
    (TypeError, (), "Type error!")
) == 2

# And, if an exceptional situation occurred, it returns the result of the corresponding expression.
@test @handler_case(
    square_root(-1),
    (DomainError, (), "Domain error!"),
    (TypeError, (), "Type error!")
) == "Domain error!"
@test @handler_case(
    square_root(""),
    (DomainError, (), "Domain error!"),
    (TypeError, (), "Type error!")
) == "Type error!"

# You can add a parameter to use the exception object within the expression.
@test @handler_case(
    square_root(-1),
    (DomainError, (e), "Error: tried to compute the square root of $(e.val).")
) == "Error: tried to compute the square root of -1."

# You can also add a case for when no exceptional situation occurs, which takes the result of the first expression as an argument. The no error case is identified by a literal "nothing" in the first element of the tuple.
@test @handler_case(
    square_root(4),
    (DomainError, (e), "Error: tried to compute the square root of $(e.val)."),
    (nothing, (result), "The result is $(result)!")
) == "The result is 2.0!"

# Only one of such cases is allowed.
@test_throws ErrorException @macroexpand @handler_case(
    square_root(4),
    (nothing, (result), 1),
    (nothing, (result), 2)
)

# As in Common Lisp, @handler_case will stop the execution of the expression as soon as exception with its type contained in the list is signaled. This means that you can't invoke restarts from inside @handler_case.
@test_throws UndefinedRestartException @handler_case(
    square_root(-1),
    (DomainError, (), invoke_restart(:return_zero))
)

# You can, however, return from functions and break from loops from inside @handler_case.
function square_root_vector_return(input)
    output = Vector()
    for value in input
        @handler_case(
            push!(output, square_root(value)),
            (DomainError, (), return "Error!")
        )
    end
    output
end
@test square_root_vector_return([0, 1, 4]) == [0, 1, 2]
@test square_root_vector_return([0, -1, 4]) == "Error!"

function square_root_vector_break(input)
    output = Vector()
    for value in input
        @handler_case(
            push!(output, square_root(value)),
            (DomainError, (), break)
        )
    end
    output
end
@test square_root_vector_break([0, 1, 4]) == [0, 1, 2]
@test square_root_vector_break([0, -1, 4]) == [0]

# @handler_case evaluates each of its arguments only once.
@test let expr_eval_count = 0, type_eval_count = 0
    @handler_case(
        (expr_eval_count += 1; square_root(0)),
        ((type_eval_count += 1; DomainError), (), nothing)
    )
    expr_eval_count == 1 && type_eval_count == 1
end
