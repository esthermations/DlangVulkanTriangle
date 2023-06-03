module math;

import std.stdio : writeln;

struct Vector(T, size_t Dimension)
{
   T[Dimension] data;
   alias data this;

   private alias Self = Vector!(T, Dimension);

   ref Self opOpAssign(string op)(Self other)
   {
      this = opBinary!(op)(other);
      return this;
   }

   Self opBinary(string op)(Self rhs) const
   {
      Self result;
      result.data[] = mixin("this.data[] " ~ op ~ " rhs.data[]");
      return result;
   }

   unittest{ assert(v4(1, 2, 3, 4) + v4(4, 3, 2, 1) == v4(5, 5, 5, 5)); }
   unittest{ assert(v4(1, 2, 3, 4) - v4(4, 3, 2, 1) == v4(-3, -1, 1, 3)); }

   static if (Dimension >= 1)
   {
      ref inout(T) x() inout { return data[0]; }
      alias r = x;
   }

   static if (Dimension == 1)
   {
      this(T x) { this.data[0] = x; }
   }

   static if (Dimension >= 2)
   {
      ref inout(T) y() inout { return data[1]; }
      alias g = y;
  }

   static if (Dimension == 2)
   {
      this(T x, T y) { this.data[] = [x, y]; }
   }

   static if (Dimension >= 3)
   {
      ref inout(T) z() inout { return data[2]; }
      alias b = z;
   }

   static if (Dimension == 3)
   {
      private alias V2 = Vector!(T, 2);

      this(T x, T y, T z) { this.data[] = [x, y, z]; }
      this(V2 v, T z)     { this.data[] = [v.x, v.y, z]; }
   }

   static if (Dimension >= 4)
   {
      ref inout(T) w() inout { return data[3]; }
      alias a = w;
   }

   static if (Dimension == 4)
   {
      private alias V2 = Vector!(T, 2);
      private alias V3 = Vector!(T, 3);

      this(T x, T y, T z, T w) { this.data[] = [x, y, z, w]; }
      this(V2 v, T z, T w)     { this.data[] = [v.x, v.y, z, w]; }
      this(V3 v, T w)          { this.data[] = [v.x, v.y, v.z, w]; }

      unittest { assert(v4(v3(0, 1, 2), 3) == v4(0, 1, 2, 3)); }
   }
}

unittest
{
   auto v = v4(1, 2, 3, 4);
   v.a += 10;
   assert(v.a == 14);
   assert(v.w == 14);
}


alias v2 = Vector!(float, 2);
alias v3 = Vector!(float, 3);
alias v4 = Vector!(float, 4);

//
// Matrix
//

struct Matrix(T, size_t Dimension)
{
   T[Dimension * Dimension] data;
   alias data this;

   private alias Self = Matrix!(T, Dimension);

   this(T[Dimension * Dimension] arr...)
   {
      this.data[] = arr[];
   }

   static auto filledWith(T value)
   {
      Self result;
      result.data[] = value;
      return result;
   }

   static auto identity()
   {
      Self m;
      foreach (i; 0 .. Dimension)
      {
         foreach (j; 0 .. Dimension)
         {
            const index = (i * Dimension) + j;
            const value = (i == j) ? 1 : 0;
            m.data[index] = value;
         }
      }
      return m;
   }

   Self opBinary(string op : "-")(Self rhs) const
   {
      Self result;
      result.data[] = this.data[] - rhs.data[];
      return result;
   }
}

alias m3 = Matrix!(float, 3);
alias m4 = Matrix!(float, 4);

unittest
{
   m4 m = m4.identity();
   assert(m[ 0] == 1);
   assert(m[ 4] == 1);
   assert(m[ 8] == 1);
   assert(m[12] == 1);
}

//
// Methods
//

pure auto dot(T, size_t Dimension)(Vector!(T, Dimension) a, Vector!(T, Dimension) b)
{
   T[Dimension] result;
   foreach (i; 0 .. Dimension)
   {
      result[i] = a.data[i] * b.data[i];
   }
   import std.algorithm : sum;
   return sum(result[]);
}

pure auto cross(T, size_t Dimension)
   (in Vector!(T, Dimension) a, in Vector!(T, Dimension) b)
{
   return a;
}

pure auto scale(T, size_t Dimension)
   (in Matrix!(T, Dimension) m, in T amount)
{
   return m;
}

alias scaling = scale;

pure auto translate(T, size_t Dimension)
   (in Matrix!(T, Dimension) m, in Vector!(T, Dimension) pos)
{
   return m;
}

pure m4 translate(T)(in m4 m, in v3 pos)
{
   m4 result = m;
   return result;
}

pure auto transpose(T, size_t Dimension)(in Matrix!(T, Dimension) m)
{
   Matrix!(T, Dimension) result;
   foreach(i; 0 .. Dimension)
   {
      foreach(j; 0 .. Dimension)
      {
         const srcIdx = (i * Dimension) + j;
         const dstIdx = (j * Dimension) + i;
         result[dstIdx] = m[srcIdx];
      }
   }
   return result;
}

pure auto normalise(T, size_t Dimension)(in Vector!(T, Dimension) v)
{
   // TODO
   return v;
}

pure auto normalise(T, size_t Dimension)(in Matrix!(T, Dimension) m)
{
   return m;
}
alias normalized = normalise;
