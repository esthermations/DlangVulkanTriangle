module ecs;

/**
 */
public struct Entity
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

/**
 */
public class Component(T)
{
   public ref T opIndex(Entity e)
   {
      return m_Storage.require(e);
   }

   private T[Entity] m_Storage;
}

private unittest
{
   const e = Entity.Create;
   auto health = new Component!int;
   health[e] = 100;
   assert(health[e] == 100);
}
