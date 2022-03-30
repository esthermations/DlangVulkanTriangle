module units;
import unit_threaded;

/**
    Types for representing units or putting constraints on values to ensure
    that they make sense.
*/

import std.traits;

struct Constrained(BaseType, alias Constraint)
    if (isBuiltinType!BaseType /* && isCallable!Constraint */)
{
    BaseType value;
    alias value this;
    static assert(this.sizeof == value.sizeof);

    this(BaseType initialValue) {
        value = initialValue;
    }

    void opAssign(BaseType newValue) {
        value = newValue;
    }

    auto ref opUnary(string op)() {
        switch (op) {
            case "--": return value -= 1;
            case "++": return value += 1;
            default: assert(0);
        }
    }

    auto ref opOpAssign(string op, BaseType)(BaseType rhs) {
        switch (op) {
            case "*": static if(__traits(compiles, value *= rhs)) value *= rhs; break;
            case "+": static if(__traits(compiles, value += rhs)) value += rhs; break;
            case "-": static if(__traits(compiles, value -= rhs)) value -= rhs; break;
            case "/": static if(__traits(compiles, value /= rhs)) value /= rhs; break;
            case "%": static if(__traits(compiles, value %= rhs)) value %= rhs; break;
            case "&": static if(__traits(compiles, value &= rhs)) value &= rhs; break;
            case "|": static if(__traits(compiles, value |= rhs)) value |= rhs; break;
            case "^": static if(__traits(compiles, value ^= rhs)) value ^= rhs; break;
            case "^^": static if(__traits(compiles, value ^^= rhs)) value ^^= rhs; break;
            case "<<": static if(__traits(compiles, value <<= rhs)) value <<= rhs; break;
            case ">>": static if(__traits(compiles, value >>= rhs)) value >>= rhs; break;
            case ">>>": static if(__traits(compiles, value >>>= rhs)) value >>>= rhs; break; // is this logical right-shift?
            case "~": static if(__traits(compiles, value ~= rhs)) value ~= rhs; break;
            default: assert(0);
        }
        return value;
    }

    invariant(Constraint(value));
}

alias NonNegative (T)               = Constrained!(T, x => x >= T(0));
alias Positive    (T)               = Constrained!(T, x => x > T(0));
alias Ranged      (T, T Min, T Max) = Constrained!(T, x => (x >= Min && x <= Max));

@ShouldFail unittest { auto s = NonNegative!float(-0.0001); }
@ShouldFail unittest { auto s = NonNegative!float(1.0); s = -1.0; }
@ShouldFail unittest { auto s = NonNegative!int(10); s *= -1; }
@ShouldFail unittest { auto s = NonNegative!int(1); s |= ~0; }
@ShouldFail unittest { auto s = Positive!int(-1); }
@ShouldFail unittest { auto s = Positive!int(0); }
@ShouldFail unittest { auto s = Positive!int(1); s *= -1; }
@ShouldFail unittest { auto s = Positive!int(1); s--; }
@ShouldFail unittest { auto s = Positive!int(1); s -= 2; }
            unittest { auto s = Positive!int(1); s *= 100; s -= 20; }

alias Scale   (T) = NonNegative!(T);
alias Percent (T) = Ranged!(T, T(0), T(100));

@ShouldFail unittest { auto p = Percent!double(0.0); p -= 1.0; }

struct Angle(T) {
    T radians; static assert(this.sizeof == radians.sizeof);

    T asRadians() immutable {
        return radians;
    }

    T asDegrees() immutable {
        import util : toDegrees;
        return toDegrees(radians);
    }
}
