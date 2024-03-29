import std.stdio;
import std.experimental.logger : log;

import math;

void printMatrix(bool rowMajor = true)(m4 mat)
{
   foreach (i; 0 .. 4)
   {
      foreach (j; 0 .. 4)
      {
         static if (rowMajor)
         {
            writef("\t%+.3f", mat[j][i]);
         }
         else
         {
            writef("\t%+.3f", mat[i][j]);
         }
      }
      writeln();
   }
}

/**
    Utility functions for the game engine, currently mostly Vulkan-related.
*/
enum Y_UP = +1.0f;
enum Y_DOWN = -Y_UP;
enum X_LEFT = -1.0f;
enum X_RIGHT = -X_LEFT;
enum Z_BACKWARDS = +1.0f;
enum Z_FORWARDS = -Z_BACKWARDS;

import std.math : abs;

enum up        = ((float f) => abs(f) * Y_UP);
enum down      = ((float f) => abs(f) * Y_DOWN);
enum left      = ((float f) => abs(f) * X_LEFT);
enum right     = ((float f) => abs(f) * X_RIGHT);
enum forwards  = ((float f) => abs(f) * Z_FORWARDS);
enum backwards = ((float f) => abs(f) * Z_BACKWARDS);

pure auto abs(T, size_t Dim)(Matrix!(T, Dim) m)
{
   m4 ret;
   foreach (i, x; m)
   {
      static import std.math;
      ret[i] = std.math.abs(x);
   }
   return ret;
}

unittest { assert(m4.filledWith(-1).abs() ==  m4.filledWith(1)); }

bool approxEqual(in m4 a, in m4 b) pure
{
   immutable epsilon = 1e-4f;
   immutable absDiff = abs(a - b);

   import std.algorithm : all;
   return absDiff[].all!(x => x < epsilon);
}

unittest { assert(approxEqual(m4.filledWith(1), m4.filledWith(1.0001))); }

/// My own lookAt implementation, taking into account that GLM's matrices are
/// stored row-major.
m4 lookAt(v3 cameraPosition, v3 targetPosition, v3 up)
{
   v3 normalise(v3 v) pure
   {
      return v.normalized;
   }

   immutable forward = normalise(cameraPosition - targetPosition);
   immutable side = normalise(cross(up, forward));
   immutable newUp = normalise(cross(forward, side));

   //debug log("forward: ", forward);
   //debug log("side   : ", side);
   //debug log("newUp  : ", newUp);

   return m4(
      [ side.x, newUp.x, forward.x, 0.0,
        side.y, newUp.y, forward.y, 0.0,
        side.z, newUp.z, forward.z, 0.0,

        -dot(cameraPosition, side),
        -dot(cameraPosition, newUp),
        -dot(cameraPosition, forward),
        1.0,
      ]
   );
}

unittest
{
   immutable view = lookAt(v3(2.0, 2.0, 2.0), v3(0, 0, 0), v3(0, 0, 1));
   immutable expected = m4(
      -0.707, -0.408, +0.577, +0.000,
      +0.707, -0.408, +0.577, +0.000,
      +0.000, +0.816, +0.577, +0.000,
      -0.000, -0.000, -3.464, +1.000,
   );
   assert(approxEqual(view, expected));
}

unittest
{
   immutable view = lookAt(v3(0, 5, 0), v3(), v3(1, 0, 0));
   immutable expected = m4(
      +0.000, +0.000, +1.000, -0.000,
      +1.000, +0.000, +0.000, -0.000,
      +0.000, +1.000, +0.000, -5.000,
      +0.000, +0.000, +0.000, +1.000,
   ).transpose();
   assert(approxEqual(view, expected));
}

/// Don't use this one. Use the one that takes fovDegrees, below. This is
/// correct but not really user-friendly.
pure m4 perspective(float top, float bottom, float left, float right, float near, float far) @nogc nothrow
{
   immutable dx = right - left;
   immutable dy = top - bottom;
   immutable dz = far - near;

   m4 ret = m4(
      [2.0 * (near / dx), 0, (right + left) / dx, 0,
      0, 2.0 * (near / dy), (top + bottom) / dy, 0,
      0, 0, -(far + near) / dz, -2.0 * far * near / dz,
      0, 0, -1, 0,]
   );
   return ret;
}

/// Converts degrees to radians.
T toRadians(T)(T degrees) pure @nogc nothrow
{
   import std.math : PI;
   return (PI / 180.0) * degrees;
}

T toDegrees(T)(T radians) pure @nogc nothrow
{
   import std.math : PI;

   return (180.0 / PI) * radians;
}

/// Calculate a projection matrix using the given fov, aspect ratio, and near
/// and far planes.
m4 perspective(float fovDegrees, float aspectRatio, float near, float far) pure @nogc nothrow
{
   import std.math : tan;

   immutable top = (near * tan(0.5 * toRadians(fovDegrees)));
   immutable bottom = -top;
   immutable right = top * aspectRatio;
   immutable left = -right;
   return perspective(top, bottom, left, right, near, far);
}

unittest
{
   immutable aspectRatio = 1280.0 / 720.0;
   immutable proj = perspective(60.0, aspectRatio, 1.0, 200.0);
   immutable expected = m4(
      +0.97428, +0.00000, +0.00000, +0.00000,
      +0.00000, +1.73205, +0.00000, +0.00000,
      +0.00000, +0.00000, -1.01005, -2.01005,
      +0.00000, +0.00000, -1.00000, +0.00000,
   );
   assert(approxEqual(proj, expected));
}

import std.string : toStringz;

enum AnsiColour
{
   RED = "\033[1;31m",
   GREEN = "\033[1;32m",
   YELLOW = "\033[1;33m",
   BLUE = "\033[1;34m",
   MAGENTA = "\033[1;35m",
   CYAN = "\033[1;36m",
   DEFAULT = "\033[39;49m",
}

string yellow(string s)
{
   return AnsiColour.YELLOW ~ s ~ AnsiColour.DEFAULT;
}

string green(string s)
{
   return AnsiColour.GREEN ~ s ~ AnsiColour.DEFAULT;
}

string red(string s)
{
   return AnsiColour.RED ~ s ~ AnsiColour.DEFAULT;
}

string cyan(string s)
{
   return AnsiColour.CYAN ~ s ~ AnsiColour.DEFAULT;
}

string blue(string s)
{
   return AnsiColour.BLUE ~ s ~ AnsiColour.DEFAULT;
}

string magenta(string s)
{
   return AnsiColour.MAGENTA ~ s ~ AnsiColour.DEFAULT;
}

// void log(AnsiColour colour = AnsiColour.DEFAULT, ArgTypes...)(ArgTypes args)
// {
//    static import globals;

//    stderr.writeln("Frame ", globals.frameNumber, ": ", args);
// }

class VulkanError : Exception
{
   this(string msg, string file = __FILE__, size_t line = __LINE__)
   {
      super(msg, file, line);
   }
}

auto check(alias func, ArgTypes...)(
   auto ref ArgTypes args, // Grabbing the callsite information...
   string callsiteFunction = __FUNCTION__,
   string callsiteFile = __FILE__,
   string callsitePrettyFunction = __PRETTY_FUNCTION__,
   string callsiteModule = __MODULE__,
   int callsiteLine = __LINE__
)
{
   enum functionName = __traits(identifier, func);
   auto errors = func(args);
   debug log(functionName, " -> ", errors, " @ ", callsiteModule, ":", callsiteLine);
   if (errors)
   {
      throw new VulkanError("Non-success return code from Vulkan call: " ~ functionName);
   }
   return errors;
}

auto ref logWhileDoing(alias func, ArgTypes...)(
   auto ref ArgTypes args, // Grabbing the callsite information...
   string callsiteFunction = __FUNCTION__,
   string callsiteFile = __FILE__,
   string callsitePrettyFunction = __PRETTY_FUNCTION__,
   string callsiteModule = __MODULE__,
   int callsiteLine = __LINE__
)
{
   enum functionName = __traits(identifier, func);
   debug log("Doing: ", functionName, " @ ", callsiteModule, ":", callsiteLine);

   static if (!__traits(isSame, typeof(func(args)), void))
   {
      return func(args);
   }
   else
   {
      func(args);
   }
}

import std.range.primitives : isInputRange, isInfinite;

bool containsDuplicates(T)(T sequence) if (isInputRange!T && !isInfinite!T)
{
   import std.algorithm : sort, uniq;
   import std.range : walkLength;

   auto s = sequence;
   auto u = sequence.sort.uniq;
   auto sl = s.walkLength;
   auto ul = u.walkLength;

   log("Sequence of length ", sl, " : ", s);
   log("Unique   of length ", ul, " : ", u);

   return sl == ul;
}

unittest
{
   assert([1, 1, 2, 3].containsDuplicates);
}

unittest
{
   assert(![1, 2, 3].containsDuplicates);
}

unittest
{
   struct Thing
   {
      int x, y;

      int opCmp(ref const Thing t) const
      {
         if (this.x < t.x)
            return -1;
         if (t.x > this.x)
            return +1;
         if (this.y < t.y)
            return -1;
         if (t.y > this.y)
            return +1;
         return 0;
      }
   }

   Thing[100] things;
   foreach (int i, ref t; things)
   {
      t = Thing(i, 100);
   }
   assert(!things[].containsDuplicates);
}

uint GetLengthAsUint(T)(T[] someArray)
{
   return cast(uint) someArray.length;
}
