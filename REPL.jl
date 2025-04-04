include("ExceptionalExtended.jl")
using .ExceptionalExtended

function retirable_eval(code)
    with_restart(
        :retry => (
            () -> retirable_eval(code),
            :report, () -> "Retry evaluation request"
        ),
        :abort => (
            () -> throw(exception),
            :report, () -> "Abort and throw the error"
        )
    ) do
        eval(code)
    end
end

while true
    print("> ")
    line = Meta.parse(readline())
    try
        println(retirable_eval(line))
    catch e
        print("ERROR: ")
        showerror(stderr, e)
        Base.show_backtrace(stdout, catch_backtrace())
        println("")
    end
end
