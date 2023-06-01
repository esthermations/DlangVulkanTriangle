module ecs;

alias FrameNumber = uint;

struct Entity
{
   public static Entity Create()
   {
      static IdType nextId = 0;
      return Entity(nextId++);
   }

   alias IdType = uint;
   IdType id;
   alias id this;

   static assert(Entity.sizeof == id.sizeof);
}

class Component(T)
{
   public static alias Type = T;

   public ref inout(T) opIndex(Entity e) inout
   {
      return m_Storage.require(e);
   }

   public FrameNumber GetLastUpdated(in Entity e) inout
   {
      return m_LastUpdated[e];
   }

   private FrameNumber[Entity] m_LastUpdated;
   private T[Entity] m_Storage;
}

class System(components...) if (is(components[0] == Component))
{
   private auto m_Comps = components.array;

   this(void function() kernel)
   {
   }

   public void Execute()
   {
   }
}

unittest
{
   //const e = Entity.Create;
   //auto health = new Component!int;
   //health[e] = 100;
   //assert(health[e] == 100);
}
