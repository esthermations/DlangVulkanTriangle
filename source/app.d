import std.stdio;
import std.exception;
import std.experimental.logger;
import erupted;
import glfw3.api;
import gl3n.linalg;

import util;
import globals;
import game;
import renderer;

void main() {

    import core.time;
    Globals.programT0 = MonoTime.currTime();

    Frame initialFrame;

    auto player      = initialFrame.createEntity;
    auto camera      = initialFrame.createEntity;
    auto theStranger = initialFrame.createEntity;

    {
        alias f = initialFrame;

        f.position    [theStranger] = vec3(0);
        f.scale       [theStranger] = 1.0;
        f.velocity    [theStranger] = vec3(0);
        f.acceleration[theStranger] = vec3(0);

        f.position    [player]       = vec3(0);
        f.scale       [player]       = 1.0;
        f.velocity    [player]       = vec3(0);
        f.acceleration[player]       = vec3(0);
        f.controlledByPlayer[player] = true;

        f.position    [camera]      = vec3(0.0, 5.up, 5.backwards);
        f.lookAtTarget[camera]      = f.position[player];
    }

    // Init GLFW

    glfwInit();
    scope (exit) glfwTerminate();

    enforce(glfwVulkanSupported(), "No Vulkan support from GLFW!");

    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE);

    Globals.window = glfwCreateWindow(
        Globals.windowWidth, 
        Globals.windowHeight, 
        "Carl", 
        null, 
        null
    );
    scope (exit) glfwDestroyWindow(Globals.window);

    {
        import glfw_callbacks;
        glfwSetFramebufferSizeCallback(Globals.window, &framebufferResized);
        glfwSetKeyCallback(Globals.window, &keyPressed);
    }

    // Init renderer

    Renderer renderer;

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
        pApplicationName : "Hello Triangle",
        apiVersion       : VK_MAKE_VERSION(1, 1, 0),
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
        ObjData model = parseObj("./models/Barrel02.obj");
        vertices.length = model.positions.length;
        foreach (i; 0 .. vertices.length) {
            vertices[i].position = model.positions[i];
            vertices[i].normal   = model.normals[i];
        }
    }

    // Create vertex buffer using those vertices

    auto playerVertexBuffer = renderer.createBuffer!Vertex(
        VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, 
        ( VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | 
          VK_MEMORY_PROPERTY_HOST_COHERENT_BIT ),
        vertices.length,
    );

    initialFrame.vertexBuffer[player] = playerVertexBuffer;

    /*
    ---------------------------------------------------------------------------
    --  Main Loop
    ---------------------------------------------------------------------------
    */

    uint frameNumber = 0;

    Frame thisFrame = game.tick(initialFrame, renderer);

    //while (!glfwWindowShouldClose(Globals.window)) {
        thisFrame = game.tick(thisFrame, renderer);
        renderer.render(thisFrame);
    //} // End of main loop

    renderer.cleanup();
}