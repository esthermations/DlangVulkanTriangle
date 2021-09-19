import std.stdio;
import std.exception;
import std.experimental.logger;
import std.conv : to;
import erupted;
import glfw3.api;
import gl3n.linalg;

import util;
static import globals;
import game;
import renderer;

void main() {

    import core.time;

    debug log("Got here!");

    Frame *initialFrame = new Frame;

    initialFrame.imageIndex = 0;
    initialFrame.projection = util.perspective(
        globals.verticalFieldOfView,
        globals.aspectRatio,
        globals.nearPlane,
        globals.farPlane
    );

    auto player      = initialFrame.ecs.createEntity;
    auto camera      = initialFrame.ecs.createEntity;

    {
        initialFrame.ecs.position           [player] = vec3(0);
        initialFrame.ecs.scale              [player] = 10.0;
        initialFrame.ecs.velocity           [player] = vec3(0);
        initialFrame.ecs.acceleration       [player] = vec3(0);
        initialFrame.ecs.controlledByPlayer [player] = true;

        initialFrame.ecs.position           [camera] = vec3(0.0, 5.up, 5.backwards);
        initialFrame.ecs.lookAtTargetEntity [camera] = player;
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
    initialFrame.ecs.vertexBuffer[player] = barrelVertexBuffer;

    foreach (i; 0 .. 990) {
        auto e = initialFrame.ecs.createEntity();

        import std.random : uniform;

        float x = uniform(-10.0, 10.0);
        float y = uniform(-10.0, 10.0);
        float z = uniform(-10.0, 10.0);

        initialFrame.ecs.vertexBuffer[e] = barrelVertexBuffer;
        initialFrame.ecs.position    [e] = vec3(x, y, z);
        initialFrame.ecs.scale       [e] = 0.001 + (i % 5) * 0.01;
    }

    /*
    ---------------------------------------------------------------------------
    --  Main Loop
    ---------------------------------------------------------------------------
    */


    Frame[] framesInFlight;
    framesInFlight.length = globals.numSwapchainImages;

    size_t currFrame = 0;
    framesInFlight[currFrame] = game.tick(initialFrame, renderer);

    import core.thread.osthread;

    while (!glfwWindowShouldClose(globals.window)) {

        renderer.render(framesInFlight[currFrame]);
        framesInFlight[currFrame] = game.tick(&framesInFlight[currFrame], renderer);

        debug log ("current frame image index is " ~ framesInFlight[currFrame].imageIndex.to!string);

        // Advance to the next Frame struct
        currFrame = (currFrame + 1) % framesInFlight.length;
    } // End of main loop

    renderer.cleanupBuffer!(Vertex)(barrelVertexBuffer);
    renderer.cleanup();
}