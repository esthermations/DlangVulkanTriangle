import std.stdio;
import std.exception;
import std.experimental.logger;
static import std.concurrency;

import erupted;
import bindbc.glfw;

mixin(bindGLFW_Vulkan);

static import globals;
import util;
import game;
import renderer;
import ecs;
import math;

void main()
{
   globals.mainThreadTid = std.concurrency.thisTid();

   import core.time;

   Frame initialFrame;

   initialFrame.imageIndex = 0;
   initialFrame.projection = util.perspective(
      globals.verticalFieldOfView,
      globals.aspectRatio,
      globals.nearPlane,
      globals.farPlane
   );

   auto player = Entity.Create();
   auto camera = Entity.Create();
   auto theStranger = Entity.Create();

   {
      alias f = initialFrame;

      f.position[player] = v3(0);
      f.scale[player] = Scale(1.0);
      f.velocity[player] = v3(0);
      f.acceleration[player] = v3(0);
      f.controlledByPlayer[player] = true;

      f.position[camera] = v3(0.0, 5.up, 5.backwards);
      f.lookAtTargetEntity[camera] = player;
   }

   // Init GLFW

   const GLFWSupport glfwOk = loadGLFW();
   assert(glfwOk == glfwSupport);

   const GLFWSupport glfwVulkanOk = loadGLFW_Vulkan();
   assert(glfwVulkanOk == glfwSupport);

   glfwInit();
   scope (exit)
      glfwTerminate();

   enforce(glfwVulkanSupported(), "No Vulkan support from GLFW!");

   glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
   glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE);

   globals.window = glfwCreateWindow(
      globals.windowWidth,
      globals.windowHeight,
      "Carl",
      null,
      null
   );
   scope (exit)
      glfwDestroyWindow(globals.window);

   {
      import glfw_callbacks;

      glfwSetFramebufferSizeCallback(globals.window, &framebufferResized);
      glfwSetKeyCallback(globals.window, &keyPressed);
   }

   // Init renderer

   Renderer renderer = new Renderer();

   import std.string : toStringz;

   const(char)*[] requiredLayers = [
      "VK_LAYER_KHRONOS_validation".toStringz
   ];

   const(char)*[] requiredDeviceExtensions = [
      VK_KHR_SWAPCHAIN_EXTENSION_NAME,
      VK_KHR_MAINTENANCE1_EXTENSION_NAME
   ];

   const(char)*[] requiredInstanceExtensions = [
      VK_EXT_DEBUG_UTILS_EXTENSION_NAME,
   ];

   VkApplicationInfo appInfo = {
      pApplicationName: "Hello Triangle",
      apiVersion: VK_MAKE_API_VERSION(0, 1, 1, 0),
   };

   renderer.initialise(
      appInfo,
      requiredLayers,
      requiredInstanceExtensions,
      requiredDeviceExtensions,
   );

   debug log("Finished initialising renderer!");

   // Import some 3D models

   Vertex[] vertices;

   {
      import obj;

      ObjData model = parseObj("./models/cube.obj");
      vertices.length = model.positions.length;
      foreach (i; 0 .. vertices.length)
      {
         vertices[i].position = model.positions[i];
         vertices[i].normal = model.normals[i];
      }
   }

   // Create vertex buffer using those vertices

   auto barrelVertexBuffer = renderer.CreateBuffer!Vertex(
      VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
      (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
         VK_MEMORY_PROPERTY_HOST_COHERENT_BIT),
      vertices.length,
   );

   barrelVertexBuffer.MapMemoryAndSetData(vertices);
   initialFrame.vertexBuffer[player] = barrelVertexBuffer;

   foreach (i; 0 .. 100)
   {
      auto e = Entity.Create();

      import std.random : uniform;

      float x = uniform(-10.0, 10.0);
      float y = uniform(-10.0, 10.0);
      float z = uniform(-10.0, 10.0);

      initialFrame.vertexBuffer[e] = barrelVertexBuffer;
      initialFrame.position[e] = v3(x, y, z);
      initialFrame.scale[e] = Scale(0.0 + 0.1 * (i % 5));
   }

   /*
    ---------------------------------------------------------------------------
    --  Main Loop
    ---------------------------------------------------------------------------
    */

   auto imageIndex = renderer.NextFrame();
   Frame thisFrame = game.tick(initialFrame, renderer, imageIndex);

   while (!glfwWindowShouldClose(globals.window))
   {
      renderer.render(thisFrame);
      imageIndex = renderer.NextFrame();
      thisFrame = game.tick(thisFrame, renderer, imageIndex);

      ++globals.frameNumber;
      debug log("---- Next Frame ----");
   } // End of main loop

   log("Thanks for playing!");
}
