module math;

struct Vector(T, size_t Dimension)
{
   T[Dimension] data;
   alias data this;

   alias ThisVector = typeof(this);

   ref ThisVector opOpAssign(string op)(const ThisVector other)
   {
      this = opBinary!(op)(this, other);
      return this;
   }

   ThisVector opBinary(string op : "+")(ThisVector a, ThisVector b)
   {
      ThisVector result;
      foreach (i; 0 .. Dimension)
      {
         result.data[i] = a.data[i] + b.data[i];
      }
      return result;
   }

   unittest{ assert(v4(1, 2, 3, 4) + v4(4, 3, 2, 1) == v4(5, 5, 5, 5)); }

   static if (Dimension >= 1)
   {
      ref inout(T) x() inout
      {
         return data[0];
      }

      alias r = x;

      this(T x)
      {
         this.data[0] = x;
      }
   }

   static if (Dimension >= 2)
   {
      ref inout(T) y() inout
      {
         return data[1];
      }

      alias g = y;

      this(T x, T y)
      {
         this.data[0] = x;
         this.data[1] = y;
      }
   }

   static if (Dimension >= 3)
   {
      ref inout(T) z() inout
      {
         return data[2];
      }

      ref inout(T) b() inout
      {
         return data[2];
      }

      this(T x, T y, T z)
      {
         this.data[0] = x;
         this.data[1] = y;
         this.data[2] = z;
      }
   }

   static if (Dimension >= 4)
   {
      ref inout(T) w() inout
      {
         return data[3];
      }

      this(T x, T y, T z, T w)
      {
         this.data[0] = x;
         this.data[1] = y;
         this.data[2] = z;
         this.data[3] = w;
      }
   }
}

alias v2 = Vector!(float, 2);
alias v3 = Vector!(float, 3);
alias v4 = Vector!(float, 4);

struct Matrix(T, size_t Dimension)
{
   T[Dimension][Dimension] data;
   alias data this;

   static auto identity()
   {
      Matrix!(T, Dimension) m;
      static foreach (i; 0 .. Matrix.Dimension)
      {
         static foreach (j; 0 .. Matrix.Dimension)
         {
            static if (i == j)
            {
               mixin("m.data[" ~ i ~ "][" ~ j ~ "] = 1;");
            }
            else
            {
               mixin("m.data[" ~ i ~ "][" ~ j ~ "] = 0;");
            }
         }
      }
      return m;
   }
}

alias m3 = Matrix!(float, 3);
alias m4 = Matrix!(float, 4);

unittest
{
   m4 m = m4.identity();
   assert(m[0][0] == 1);
   assert(m[1][1] == 1);
   assert(m[2][2] == 1);
   assert(m[3][3] == 1);
}

//
// Methods
//

pure auto dot(T, size_t Dimension)(Vector!(T, Dimension) a, Vector!(T, Dimension) b)
{
   T[Dimension] result;
   foreach (i; 0 .. Dimension)
   {
      result[i] = a[i] * b[i];
   }

   import std.algorithm : sum;

   return result.sum;
}

pure auto scale(T, size_t Dimension)
   (in Matrix!(T, Dimension) m, in T amount)
{
   writeln(__FUNCTION__, " unimplemented");
   return m;
}

alias scaling = scale;

pure auto translate(T, size_t Dimension)
   (in Matrix!(T, Dimension) m, in Vector!(T, Dimension) pos)
{
   writeln(__FUNCTION__, " unimplemented");
   return m;
}

pure auto transpose(T, size_t Dimension)(in Matrix!(T, Dimension) m)
{
   Matrix!(T, Dimension) result;
   foreach(i; 0 .. Dimension)
   {
      foreach(j; 0 .. Dimension)
      {
         result.data[i][j] = m.data[j][i];
      }
   }
   return result;
}

pure auto normalise(T, size_t Dimension)(in Matrix!(T, Dimension) m)
{
   writeln(__FUNCTION__, " unimplemented");
   return m;
}
alias normalized = normalise;
