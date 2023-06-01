module game;

import std.algorithm;
import std.typecons : Nullable;
import std.exception : enforce;
import std.parallelism : parallel;
import std.experimental.logger : log;

import bindbc.glfw;
import erupted;

static import globals;
import ecs;
import util;
import renderer;
import math;

enum GameAction
{
   NO_ACTION,
   MOVE_FORWARDS,
   MOVE_BACKWARDS,
   MOVE_LEFT,
   MOVE_RIGHT,
   MOVE_UP,
   MOVE_DOWN,
   PRINT_DEBUG_INFO,
   QUIT_GAME,
}

enum MOVEMENT_IMPULSE = 0.001;

// Let's declare some units...
static import units;

alias Scale = units.Scale!float;
alias Angle = units.Angle!float;

struct Frame
{
   /// An index into the Vulkan swapchain corresponding to the image this frame
   /// will be rendered into.
   uint imageIndex;

   m4 projection; /// Projection uniform

   /// Has the player requested the specified action this frame?
   bool[GameAction.max + 1] actionRequested = [false];

   // Components
   v3[Entity] position;
   v3[Entity] velocity;
   v3[Entity] acceleration;
   Entity[Entity] lookAtTargetEntity;
   bool[Entity] controlledByPlayer;
   Scale[Entity] scale;
   Angle[Entity] rotation;
   m4[Entity] modelMatrix;
   m4[Entity] viewMatrix;
   VertexBuffer[Entity] vertexBuffer;
}

Frame tick(Frame previousFrame, ref Renderer renderer, uint imageIndex)
{
   import std.algorithm : map, fold, setIntersection, each;

   debug log("Tick for frame ", globals.frameNumber);

   Frame thisFrame = {
      projection: previousFrame.projection,
      position: previousFrame.position,
      velocity: previousFrame.velocity,
      acceleration: previousFrame.acceleration,
      lookAtTargetEntity: previousFrame.lookAtTargetEntity,
      controlledByPlayer: previousFrame.controlledByPlayer,
      scale: previousFrame.scale,
      modelMatrix: previousFrame.modelMatrix,
      viewMatrix: previousFrame.viewMatrix,
      vertexBuffer: previousFrame.vertexBuffer,
      actionRequested: [false],
   };

   glfwSetWindowUserPointer(globals.window, &thisFrame);

   // Poll GLFW events. This may result in the frame's state being modified
   // through the user pointer we just set, by the functions in
   // glfw_callbacks.d.
   glfwPollEvents();

   thisFrame.imageIndex = imageIndex;

   /*
        Run systems
    */

   // Update velocities

   void updateVelocities()
   {
      auto velEnts = entitiesWithComponent(thisFrame.velocity);
      auto accEnts = entitiesWithComponent(thisFrame.acceleration);
      auto ents = setIntersection(velEnts, accEnts);
      debug (ecs)
         log(ents);
      foreach (e; ents)
      {
         thisFrame.velocity[e] += thisFrame.acceleration[e];
      }
   }

   // Update positions

   void updatePositions()
   {
      auto posEnts = entitiesWithComponent(thisFrame.position);
      auto velEnts = entitiesWithComponent(thisFrame.velocity);
      auto ents = setIntersection(posEnts, velEnts);
      debug (ecs)
         log(ents);
      foreach (e; ents.parallel)
      {
         thisFrame.position[e] += thisFrame.velocity[e];
      }
   }

   // Update model matrices

   void updateModelMatrices()
   {
      auto posEnts = entitiesWithComponent(thisFrame.position);
      auto sclEnts = entitiesWithComponent(thisFrame.scale);
      auto ents = setIntersection(posEnts, sclEnts);
      debug (ecs)
         log(ents);

      foreach (e; ents.parallel)
      {
         auto scale = thisFrame.scale[e];
         auto position = thisFrame.position[e];
         thisFrame.modelMatrix[e] = m4.identity
            .scale(scale)
            .translate(position)
            .transposed();
      }
   }

   // Update camera view matrices

   void updateViewMatrices()
   {
      auto lookAtEnts = entitiesWithComponent(thisFrame.lookAtTargetEntity);
      auto posEnts = entitiesWithComponent(thisFrame.position);
      auto cameras = setIntersection(lookAtEnts, posEnts);

      debug (ecs)
      {
         log("Entities with lookAt target: ", lookAtEnts);
         import std.algorithm : sort;

         log("Entities with position: ", posEnts.sort);
         log("Cameras (intersection of the above):", cameras);
      }

      foreach (e; cameras)
      {
         v3 eyePos = thisFrame.position[e];
         Entity targetEntity = thisFrame.lookAtTargetEntity[e];
         v3 targetPos = thisFrame.position[targetEntity];
         thisFrame.viewMatrix[e] = lookAt(eyePos, targetPos, v3(0, 1.up, 0));
      }
   }

   // Prepare updated uniform data

   Uniforms updateUniforms()
   {
      // NOTE: We're explicitly assuming here that only one entity (the
      // camera) will have a view matrix. Or at least, if there are multiple
      // view matrices, we're always using the first one.
      auto viewMatrixEnts = entitiesWithComponent(thisFrame.viewMatrix);
      debug log("There are ", viewMatrixEnts.length, " entities with a view matrix.");
      assert(viewMatrixEnts.length == 1, "No entities with a view matrix. Where is the camera?");
      auto viewMatrix = thisFrame.viewMatrix[viewMatrixEnts[0]];
      debug log("Camera entity is: ", viewMatrixEnts.front);

      auto uniformData = new Uniforms;
      uniformData.projection = thisFrame.projection;
      uniformData.view = viewMatrix;

      auto modelMatrixEnts = entitiesWithComponent(thisFrame.modelMatrix);

      uint i = 0;
      foreach (e; modelMatrixEnts)
      {
         assert(i <= uniformData.models.length);
         uniformData.models[i++] = thisFrame.modelMatrix[e];
      }

      return uniformData;
   }

   // Render vertex buffers

   void renderEntities(Uniforms ubo)
   {
      auto modelEnts = entitiesWithComponent(thisFrame.modelMatrix);
      auto vbufEnts = entitiesWithComponent(thisFrame.vertexBuffer);
      auto renderableEntities = setIntersection(modelEnts, vbufEnts);
      debug log(renderableEntities);

      renderer.beginCommandsForFrame(thisFrame.imageIndex, ubo);

      uint[VertexBuffer] counts;

      foreach (e; vbufEnts)
      {
         auto vbuf = thisFrame.vertexBuffer[e];
         counts[vbuf]++;
      }

      foreach (vbuf, count; counts)
      {
         renderer.issueRenderCommands(thisFrame.imageIndex, vbuf, count);
      }

      renderer.endCommandsForFrame(thisFrame.imageIndex);
   }

   // Set player's acceleration based on player input
   void updatePlayerAcceleration()
   {
      auto playerEntities = entitiesWithComponent(thisFrame.controlledByPlayer);
      auto accelEntities = entitiesWithComponent(thisFrame.acceleration);
      auto ents = setIntersection(playerEntities, accelEntities);

      foreach (e; ents)
      {
         v3 accel = v3(0);

         if (thisFrame.actionRequested[GameAction.MOVE_FORWARDS])
         {
            accel.z += MOVEMENT_IMPULSE.forwards;
         }
         if (thisFrame.actionRequested[GameAction.MOVE_BACKWARDS])
         {
            accel.z += MOVEMENT_IMPULSE.backwards;
         }
         if (thisFrame.actionRequested[GameAction.MOVE_RIGHT])
         {
            accel.x += MOVEMENT_IMPULSE.right;
         }
         if (thisFrame.actionRequested[GameAction.MOVE_LEFT])
         {
            accel.x += MOVEMENT_IMPULSE.left;
         }
         if (thisFrame.actionRequested[GameAction.MOVE_UP])
         {
            accel.y += MOVEMENT_IMPULSE.up;
         }
         if (thisFrame.actionRequested[GameAction.MOVE_DOWN])
         {
            accel.y += MOVEMENT_IMPULSE.down;
         }

         // Output
         thisFrame.acceleration[e] = accel;
      }
   }

   logWhileDoing!updateVelocities();
   logWhileDoing!updatePositions();
   logWhileDoing!updateModelMatrices();
   logWhileDoing!updateViewMatrices();
   logWhileDoing!updatePlayerAcceleration();
   Uniforms ubo = logWhileDoing!updateUniforms();
   logWhileDoing!renderEntities(ubo);

   if (thisFrame.actionRequested[GameAction.QUIT_GAME])
   {
      glfwSetWindowShouldClose(globals.window, GLFW_TRUE);
   }

   return thisFrame;
}

auto entitiesWithComponent(T)(T[Entity] map) pure
{
   import std.algorithm : sort;

   return map.keys.sort;
}

unittest
{
   m4[Entity] viewMatrix;
   viewMatrix[Entity(50)] = m4.identity;
   auto ents = entitiesWithComponent(viewMatrix);
   assert(ents.length == 1);
   assert(ents[0] == Entity(50));
}

/// Returns the GameAction associated with this keyboard key.
/// @key: should be a GLFW_KEY_* value.
GameAction associatedAction(int key) pure nothrow @nogc
{
   switch (key)
   {
   case GLFW_KEY_W:
      return GameAction.MOVE_FORWARDS;
   case GLFW_KEY_A:
      return GameAction.MOVE_LEFT;
   case GLFW_KEY_S:
      return GameAction.MOVE_BACKWARDS;
   case GLFW_KEY_D:
      return GameAction.MOVE_RIGHT;
   case GLFW_KEY_SPACE:
      return GameAction.MOVE_UP;
   case GLFW_KEY_LEFT_CONTROL:
      return GameAction.MOVE_DOWN;
   case GLFW_KEY_P:
      return GameAction.PRINT_DEBUG_INFO;
   case GLFW_KEY_ESCAPE:
      return GameAction.QUIT_GAME;
   default:
      return GameAction.NO_ACTION;
   }
   assert(0);
}
