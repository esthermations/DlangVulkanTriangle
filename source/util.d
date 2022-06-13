import std.stdio;
import std.concurrency : Tid, thisTid;

import gl3n.linalg;

void printMatrix(mat4 mat, bool rowMajor = true) {
    foreach (i; 0 .. 4) {
        foreach (j; 0 .. 4) {
            writef("\t%+.3f", rowMajor ? mat[j][i] : mat[i][j]);
        }
        writeln();
    }
}

/**
    Utility functions for the game engine, currently mostly Vulkan-related.
*/

enum Y_UP        = +1.0f;
enum Y_DOWN      = -Y_UP;
enum X_LEFT      = -1.0f;
enum X_RIGHT     = -X_LEFT;
enum Z_BACKWARDS = +1.0f;
enum Z_FORWARDS  = -Z_BACKWARDS;

import std.math : fabs;
immutable up        = ((float f) => Y_UP        * fabs(f));
immutable down      = ((float f) => Y_DOWN      * fabs(f));
immutable left      = ((float f) => X_LEFT      * fabs(f));
immutable right     = ((float f) => X_RIGHT     * fabs(f));
immutable forwards  = ((float f) => Z_FORWARDS  * fabs(f));
immutable backwards = ((float f) => Z_BACKWARDS * fabs(f));

mat4 abs(mat4 m) pure {
    import std.math : abs;
    mat4 ret;
    foreach (i; 0 .. 4) {
        foreach (j; 0 .. 4) {
            ret[i][j] = abs(m[i][j]);
        }
    }
    return ret;
}

unittest {
    mat4 m = mat4(-1);
    mat4 result = abs(m);
    assert(result == mat4(1));
}

bool approxEqual(mat4 a, mat4 b) pure {
    immutable epsilon = 0.001;
    immutable absDiff = abs(a - b);
    foreach (i; 0 .. 4) {
        foreach (j; 0 .. 4) {
            if (absDiff[i][j] > epsilon) {
                return false;
            }
        }
    }
    return true;
}

unittest {
    assert(approxEqual(mat4(1.0), mat4(1.0001)));
}

/// My own lookAt implementation, taking into account that GLM's matrices are
/// stored row-major.
mat4 lookAt(vec3 cameraPosition, vec3 targetPosition, vec3 up) {

    vec3 normalise(vec3 v) pure {
        return v.normalized;
    }

    immutable forward = normalise(cameraPosition - targetPosition);
    immutable side    = normalise(cross(up, forward));
    immutable newUp   = normalise(cross(forward, side));

    //debug log("forward: ", forward);
    //debug log("side   : ", side);
    //debug log("newUp  : ", newUp);

    return mat4(
        side.x, newUp.x, forward.x, 0.0,
        side.y, newUp.y, forward.y, 0.0,
        side.z, newUp.z, forward.z, 0.0,
        -dot(cameraPosition, side),
        -dot(cameraPosition, newUp),
        -dot(cameraPosition, forward),
        1.0,
    );
}

unittest {
    immutable view = lookAt(vec3(2.0, 2.0, 2.0), vec3(0, 0, 0), vec3(0, 0, 1));
    immutable expected = mat4(
        -0.707, -0.408, +0.577, +0.000,
        +0.707, -0.408, +0.577, +0.000,
        +0.000, +0.816, +0.577, +0.000,
        -0.000, -0.000, -3.464, +1.000,
     );
    assert(approxEqual(view, expected));
}

unittest {
    immutable view = lookAt(vec3(0, 5, 0), vec3(0), vec3(1, 0, 0));
    immutable expected = mat4(
        +0.000, +0.000, +1.000, -0.000,
        +1.000, +0.000, +0.000, -0.000,
        +0.000, +1.000, +0.000, -5.000,
        +0.000, +0.000, +0.000, +1.000,
    ).transposed;
    assert(approxEqual(view, expected));
}

/// Don't use this one. Use the one that takes fovDegrees, below. This is
/// correct but not really user-friendly.
mat4 perspective(float top, float bottom, float left, float right, float near, float far) pure @nogc nothrow {
    immutable dx = right - left;
    immutable dy = top - bottom;
    immutable dz = far - near;

    mat4 ret = mat4(
        2.0 * (near/dx), 0,               (right+left)/dx, 0,
        0,               2.0 * (near/dy), (top+bottom)/dy, 0,
        0,               0,               -(far+near)/dz,  -2.0*far*near/dz,
        0,               0,               -1,              0,
    );
    return ret;
}

/// Converts degrees to radians.
T toRadians(T)(T degrees) pure @nogc nothrow {
    import std.math : PI;
    return (PI / 180.0) * degrees;
}


T toDegrees(T)(T radians) pure @nogc nothrow {
    import std.math : PI;
    return (180.0 / PI) * radians;
}

/// Calculate a projection matrix using the given fov, aspect ratio, and near
/// and far planes.
mat4 perspective(float fovDegrees, float aspectRatio, float near, float far) pure @nogc nothrow {
    import std.math  : tan;
    immutable top    = (near * tan(0.5 * toRadians(fovDegrees)));
    immutable bottom = -top;
    immutable right  = top * aspectRatio;
    immutable left   = -right;
    return perspective(top, bottom, left, right, near, far);
}

unittest {
    immutable aspectRatio = 1280.0 / 720.0;
    immutable proj = perspective(60.0, aspectRatio, 1.0, 200.0);
    immutable expected = mat4(
        +0.97428, +0.00000, +0.00000, +0.00000,
        +0.00000, +1.73205, +0.00000, +0.00000,
        +0.00000, +0.00000, -1.01005, -2.01005,
        +0.00000, +0.00000, -1.00000, +0.00000,
    );
    assert(approxEqual(proj, expected));
}

import std.string : toStringz;

enum AnsiColour {
    RED     = "\033[1;31m",
    GREEN   = "\033[1;32m",
    YELLOW  = "\033[1;33m",
    BLUE    = "\033[1;34m",
    MAGENTA = "\033[1;35m",
    CYAN    = "\033[1;36m",
    DEFAULT = "\033[39;49m",
}

string yellow (string s) { return AnsiColour.YELLOW  ~ s ~ AnsiColour.DEFAULT; }
string green  (string s) { return AnsiColour.GREEN   ~ s ~ AnsiColour.DEFAULT; }
string red    (string s) { return AnsiColour.RED     ~ s ~ AnsiColour.DEFAULT; }
string cyan   (string s) { return AnsiColour.CYAN    ~ s ~ AnsiColour.DEFAULT; }
string blue   (string s) { return AnsiColour.BLUE    ~ s ~ AnsiColour.DEFAULT; }
string magenta(string s) { return AnsiColour.MAGENTA ~ s ~ AnsiColour.DEFAULT; }

void log(AnsiColour colour = AnsiColour.DEFAULT, ArgTypes...)(ArgTypes args)
{
    static import globals;
    stderr.writeln("Frame ", globals.frameNumber, ": ", args);
}


auto check(alias func, ArgTypes...)(
    auto ref ArgTypes args,
    // Grabbing the callsite information...
    string callsiteFunction = __FUNCTION__,
    string callsiteFile = __FILE__,
    string callsitePrettyFunction = __PRETTY_FUNCTION__,
    string callsiteModule = __MODULE__,
    int    callsiteLine = __LINE__
)
{
    enum functionName = __traits(identifier, func);
    auto errors = func(args);
    debug log(functionName, " -> ", errors, " @ ", callsiteModule, ":", callsiteLine);
    assert(!errors, "Non-success return code from Vulkan call: " ~ functionName);
    return errors;
}

auto ref logWhileDoing(alias func, ArgTypes...)(
    auto ref ArgTypes args,
    // Grabbing the callsite information...
    string callsiteFunction = __FUNCTION__,
    string callsiteFile = __FILE__,
    string callsitePrettyFunction = __PRETTY_FUNCTION__,
    string callsiteModule = __MODULE__,
    int    callsiteLine = __LINE__
)
{
    enum functionName = __traits(identifier, func);
    debug log("Doing: ", functionName, " @ ", callsiteModule, ":", callsiteLine);

    static if (!__traits(isSame, typeof(func(args)), void)) {
        return func(args);
    }
    else {
        func(args);
    }
}


import std.range.primitives : isInputRange, isInfinite;
bool containsDuplicates(T)(T sequence)
    if (isInputRange!T && !isInfinite!T)
{
    import std.algorithm : uniq;
    import std.range     : walkLength;

    auto s = sequence;
    auto u = sequence.uniq;
    auto sl = s.walkLength;
    auto ul = u.walkLength;

    log(__FUNCTION__, " : Sequence of length ", sl, " : ", s);
    log(__FUNCTION__, " : Unique   of length ", ul, " : ", u);

    return sl == ul;
}

unittest { assert( [1, 1, 2, 3].containsDuplicates); }
unittest { assert(![1, 2, 3].containsDuplicates); }

unittest
{
    struct Thing { int x, y; }
    Thing[] things;
    foreach (i; 0 .. 100) {
        things ~= Thing(i, 100);
    }
    assert(!things.containsDuplicates);
}

bool runningOnMainThread(Tid callsiteTid = thisTid())
{
    static import globals;
    return callsiteTid == globals.mainThreadTid;
}

uint GetLengthAsUint(T)(T[] someArray)
{
    return cast(uint) someArray.length;
}
