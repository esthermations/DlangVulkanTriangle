import std.stdio;
import std.exception;
import std.experimental.logger;
import erupted;
import glfw3.api;
import gl3n.linalg;

import util;
static import globals;
import game;
import renderer;

void main() {

    import core.time;

    Frame initialFrame;

    initialFrame.imageIndex = 0;
    initialFrame.projection = util.perspective(
        globals.verticalFieldOfView, 
        globals.aspectRatio, 
        globals.nearPlane, 
        globals.farPlane
    );

    auto player      = initialFrame.createEntity;
    auto camera      = initialFrame.createEntity;
    auto theStranger = initialFrame.createEntity;

    {
        alias f = initialFrame;

        f.position    [player]       = vec3(0);
        f.scale       [player]       = 10.0;
        f.velocity    [player]       = vec3(0);
        f.acceleration[player]       = vec3(0);
        f.controlledByPlayer[player] = true;

        f.position          [camera] = vec3(0.0, 5.up, 5.backwards);
        f.lookAtTargetEntity[camera] = player;
    }

    // Init GLFW

    glfwInit();
    scope (exit) glfwTerminate();

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
    scope (exit) glfwDestroyWindow(globals.window);

    {
        import glfw_callbacks;
        glfwSetFramebufferSizeCallback(globals.window, &framebufferResized);
        glfwSetKeyCallback(globals.window, &keyPressed);
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

    auto barrelVertexBuffer = renderer.createBuffer!Vertex(
        VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, 
        ( VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | 
          VK_MEMORY_PROPERTY_HOST_COHERENT_BIT ),
        vertices.length,
    );

    renderer.setBufferData(barrelVertexBuffer, vertices);
    initialFrame.vertexBuffer[player]      = barrelVertexBuffer;

    foreach (i; 0 .. 990) {
        auto e = initialFrame.createEntity();

        import std.random : uniform;

        float x = uniform(-10.0, 10.0);
        float y = uniform(-10.0, 10.0);
        float z = uniform(-10.0, 10.0);

        initialFrame.vertexBuffer[e] = barrelVertexBuffer;
        initialFrame.position    [e] = vec3(x, y, z);
        initialFrame.scale       [e] = 5.0 + (i % 5);
    }

    /*
    ---------------------------------------------------------------------------
    --  Main Loop
    ---------------------------------------------------------------------------
    */

    uint frameNumber = 0;

    Frame thisFrame = game.tick(initialFrame, renderer);

    import core.thread.osthread;

    while (!glfwWindowShouldClose(globals.window)) {
        renderer.render(thisFrame);
        thisFrame = game.tick(thisFrame, renderer);
    } // End of main loop

    renderer.cleanupBuffer!(Vertex)(barrelVertexBuffer);
    renderer.cleanup();
}