import std.stdio;
import std.exception;
import std.experimental.logger;
import erupted;
import glfw3.api;
import gl3n.linalg;

import util;
import globals;
import game;

/// How many frames in advance we should allow Vulkan to render.
enum MAX_FRAMES_IN_FLIGHT = 2;

void main() {

    import core.time;
    Globals.programT0 = MonoTime.currTime();

    auto camera = Game.createEntity;
    Game.position    [camera] = vec3(0.0, 5.up, 5.backwards);

    auto theStranger = Game.createEntity;
    Game.position    [theStranger] = vec3(0);
    Game.velocity    [theStranger] = vec3(0);
    Game.acceleration[theStranger] = vec3(0);

    auto player = Game.createEntity;
    Game.position    [player] = vec3(0);
    Game.velocity    [player] = vec3(0);
    Game.acceleration[player] = vec3(0);

    Game.playerEntity = player;


    glfwInit();
    scope (exit) glfwTerminate();

    enforce(glfwVulkanSupported(), "No Vulkan support from GLFW!");

    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE);

    Globals.window = glfwCreateWindow(Globals.framebufferWidth, 
                                      Globals.framebufferHeight, 
                                      "Carl", 
                                      null, 
                                      null);
    scope (exit) glfwDestroyWindow(Globals.window);

    {
        import glfw_callbacks;
        glfwSetFramebufferSizeCallback(Globals.window, &framebufferResized);
        glfwSetKeyCallback(Globals.window, &keyPressed);
    }

    /*
    ---------------------------------------------------------------------------
    --  Init Vulkan 
    ---------------------------------------------------------------------------
    */

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

    import erupted.vulkan_lib_loader;

    bool vulkanLoadedOkay = loadGlobalLevelFunctions;
    enforce(vulkanLoadedOkay, "Failed to load Vulkan functions!");

    VkApplicationInfo appInfo = {
        pApplicationName : "Hello Triangle",
        apiVersion       : VK_MAKE_VERSION(1, 1, 0),
    };

    /*
    ---------------------------------------------------------------------------
    --  Instance creation
    ---------------------------------------------------------------------------
    */

    // Validation layers!!

    uint layerCount;
    vkEnumerateInstanceLayerProperties(&layerCount, null);
    enforce(layerCount > 0, "No layers available? This is weird.");

    VkLayerProperties[] availableLayers;
    availableLayers.length = layerCount;
    vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.ptr);

    uint numRequiredLayersFound = 0;

    foreach (requiredLayer; requiredLayers) {
        import std.algorithm.searching : canFind;

        foreach (layer; availableLayers) {
            immutable string layerName = layer.layerName.idup;
            import core.stdc.string : strcmp;

            if (strcmp(requiredLayer, layerName.ptr) == 0) {
                ++numRequiredLayersFound;
                break;
            }
        }
    }

    enforce(numRequiredLayersFound == requiredLayers.length, 
            "Couldn't find all required layers!");

    // Glfw Extensions

    uint glfwExtensionCount;
    auto glfwExtensions = 
        glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

    for (auto i = 0; i < glfwExtensionCount; ++i) {
        requiredInstanceExtensions ~= glfwExtensions[i];
    }

    VkInstanceCreateInfo instanceCreateInfo = {
        pApplicationInfo        : &appInfo, 
        enabledExtensionCount   : cast(uint) requiredInstanceExtensions.length, 
        ppEnabledExtensionNames : requiredInstanceExtensions.ptr,
        enabledLayerCount       : cast(uint) requiredLayers.length,
        ppEnabledLayerNames     : requiredLayers.ptr,
    };

    // Create the instance

    VkInstance instance;
    auto instanceCreatedOkay = 
        vkCreateInstance(&instanceCreateInfo, null, &instance);
    enforce(instanceCreatedOkay == VK_SUCCESS, 
            "Failed to create VkInstance!");

    loadInstanceLevelFunctions(instance);

    // Set up debug messenger

    VkDebugUtilsMessengerEXT messenger = createDebugMessenger(instance);

    // Create rendering surface
    VkSurfaceKHR surface;

    import glfw3.vulkan : glfwCreateWindowSurface;

    {
        auto errors = cast(erupted.VkResult) glfwCreateWindowSurface(
            instance, Globals.window, null, cast(ulong*)&surface);
        enforce(!errors, "Failed to create a window surface!");
    }

    VkPhysicalDevice physicalDevice = 
        selectPhysicalDevice(instance, requiredDeviceExtensions, surface);

    // Create the device queue
    QueueFamilies queueFamilies = selectQueueFamilies(physicalDevice, surface);
    enforce(queueFamilies.isComplete);

    static float[1] queuePriorities = [1.0];
    
    VkDeviceQueueCreateInfo[] queueCreateInfos = [
        // Graphics family
        {
            queueFamilyIndex : queueFamilies.graphics.get, 
            queueCount       : 1,
            pQueuePriorities : queuePriorities.ptr,
        },
    ];

    // Only append presentFamily if it's a different family to the graphics one.
    if (queueFamilies.present.get != queueFamilies.graphics.get) {
        VkDeviceQueueCreateInfo presentQueueCreateInfo = {
            queueFamilyIndex : queueFamilies.present.get,
            queueCount       : 1,
            pQueuePriorities : queuePriorities.ptr,
        };

        queueCreateInfos ~= presentQueueCreateInfo;
    }

    VkPhysicalDeviceFeatures deviceFeatures;

    VkDeviceCreateInfo deviceCreateInfo = {
        pQueueCreateInfos       : queueCreateInfos.ptr, 
        queueCreateInfoCount    : cast(uint) queueCreateInfos.length,
        pEnabledFeatures        : &deviceFeatures,
        enabledExtensionCount   : cast(uint) requiredDeviceExtensions.length,
        ppEnabledExtensionNames : requiredDeviceExtensions.ptr,
    };

    // Logical device
    VkDevice logicalDevice;

    auto logicalDeviceCreatedOkay = 
        vkCreateDevice(physicalDevice, &deviceCreateInfo, null, &logicalDevice);
    enforce(logicalDeviceCreatedOkay == VK_SUCCESS, 
            "Failed to create VkDevice!");

    loadDeviceLevelFunctions(logicalDevice);

    VkQueue graphicsQueue;
    VkQueue presentQueue;
    //VkQueue transferQueue;

    vkGetDeviceQueue(logicalDevice, queueFamilies.graphics.get, 0, &graphicsQueue);
    vkGetDeviceQueue(logicalDevice, queueFamilies.present.get, 0, &presentQueue);
    //vkGetDeviceQueue(logicalDevice, queueFamilies.transfer.get, 0, &transferQueue);

    VkDescriptorSetLayout descriptorSetLayout;

    {
        VkDescriptorSetLayoutBinding uboLayoutBinding = {
            binding            : 0,
            descriptorType     : VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            descriptorCount    : 1,
            stageFlags         : VK_SHADER_STAGE_VERTEX_BIT,
            pImmutableSamplers : null, // may handle textures in future?
        };

        VkDescriptorSetLayoutCreateInfo layoutInfo = {
            bindingCount : 1,
            pBindings    : &uboLayoutBinding,
        };

        auto errors = vkCreateDescriptorSetLayout(
            logicalDevice, &layoutInfo, null, &descriptorSetLayout);
        enforce(!errors);
    }

    // Create descriptor pool

    VkDescriptorPool descriptorPool;

    // Create pipeline layout.

    VkPipelineLayout pipelineLayout;

    {
        VkPipelineLayoutCreateInfo createInfo = {
            setLayoutCount : 1,
            pSetLayouts    : &descriptorSetLayout,
        };

        auto errors = vkCreatePipelineLayout(
            logicalDevice, &createInfo, null, &pipelineLayout);
        enforce(!errors, "Failed to create pipeline layout");
    }

    // Create command pool

    VkCommandPool commandPool;

    {
        VkCommandPoolCreateInfo createInfo = {
            queueFamilyIndex : queueFamilies.graphics.get,
            flags            : 0,
        };

        auto errors = logicalDevice.vkCreateCommandPool(
            &createInfo, null, &commandPool);
        enforce(!errors, "Failed to create command pool.");
    }

    // Create swapchain

    auto surfaceFormat = physicalDevice.getSurfaceFormat(surface);
    auto surfaceExtent = physicalDevice.getSurfaceExtent(surface, Globals.window);

    SwapchainWithDependents swapchain = createSwapchain(
        logicalDevice,
        physicalDevice,
        surface,
        Globals.window,
        pipelineLayout,
        descriptorSetLayout,
        commandPool
    );
    
    void updateUniforms(VkDevice logicalDevice, 
                        Buffer uniformBuffer, 
                        uint currentImage) 
        in (currentImage < Globals.uniforms.length)
    {
        MonoTime currentTime = MonoTime.currTime();

        import std.conv : to;
        auto duration = to!TickDuration(currentTime - Globals.programT0);
        const float timeAsFloat = core.time.to!("seconds", float)(duration);

        float scaleFactor = 10.00;

        Globals.uniforms[currentImage].model =
            mat4.identity.scale(scaleFactor, scaleFactor, scaleFactor)
                         .translate(Game.position[Game.playerEntity].get)
                         .transposed;

        import std.math : fmod;

        Globals.uniforms[currentImage].view =
            lookAt(Game.position[camera].get, vec3(0), vec3(0, 1, 0));

        immutable float near = 1.0;
        immutable float far  = 200.0;

        Globals.uniforms[currentImage].projection =
            perspective(
                Globals.verticalFieldOfView, 
                Globals.aspectRatio, 
                near, 
                far
            );

        debug(matrices) {
            writeln("model:");
            printMatrix(Globals.uniforms[currentImage].model);

            writeln("view:");
            printMatrix(Globals.uniforms[currentImage].view);

            writeln("proj:");
            printMatrix(Globals.uniforms[currentImage].projection);
        }
        
        uniformBuffer.sendData(logicalDevice, 
                               Globals.uniforms[currentImage .. currentImage + 1]);
    }

    // Create sync objects

    VkSemaphore[MAX_FRAMES_IN_FLIGHT] imageAvailableSemaphores;
    VkSemaphore[MAX_FRAMES_IN_FLIGHT] renderFinishedSemaphores;
    VkFence[MAX_FRAMES_IN_FLIGHT]     inFlightFences;
    VkFence[]                         imagesInFlightFences;
    imagesInFlightFences.length = swapchain.imageViews.length;

    foreach (i; 0 .. MAX_FRAMES_IN_FLIGHT) {
        VkSemaphoreCreateInfo imageAvailableSemaphoreCreateInfo;
        VkSemaphoreCreateInfo renderFinishedSemaphoreCreateInfo;

        auto createImageSemaphoreResult = vkCreateSemaphore(
            logicalDevice, &imageAvailableSemaphoreCreateInfo, null, 
            &imageAvailableSemaphores[i]);

        enforce(createImageSemaphoreResult  == VK_SUCCESS);

        auto createRenderSemaphoreResult = vkCreateSemaphore(
            logicalDevice, &renderFinishedSemaphoreCreateInfo, null, 
            &renderFinishedSemaphores[i]);

        enforce(createRenderSemaphoreResult == VK_SUCCESS);

        VkFenceCreateInfo fenceInfo = {
            flags : VK_FENCE_CREATE_SIGNALED_BIT,
        };

        auto fenceCreateResult = vkCreateFence(
            logicalDevice, &fenceInfo, null, &inFlightFences[i]);
        enforce(fenceCreateResult == VK_SUCCESS);
    }

    import obj;
    //ObjData model = parseObj("./models/cube.obj");
    ObjData model = parseObj("./models/Barrel02.obj");

    Vertex[] vertices;
    vertices.length = model.positions.length;
    foreach (i; 0 .. vertices.length) {
        vertices[i].position = model.positions[i];
        vertices[i].normal   = model.normals[i];
    }

    // Create vertex buffer

    Buffer vertexBuffer = createBuffer(
        logicalDevice, 
        physicalDevice,
        vertices.length * vertices[0].sizeof,
        VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, 
        ( VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | 
          VK_MEMORY_PROPERTY_HOST_COHERENT_BIT )
    );

    vertexBuffer.sendData(logicalDevice, vertices);

    // Record commands

    issueRenderCommands(
        swapchain, surfaceExtent, pipelineLayout, vertices, vertexBuffer.buffer);

    /*
    ---------------------------------------------------------------------------
    --  Main Loop
    ---------------------------------------------------------------------------
    */

    uint frameNumber = 0;

    MonoTime frameBeginTime;

    while (!glfwWindowShouldClose(Globals.window)) {
        frameBeginTime = MonoTime.currTime();
        scope(exit) {
            Globals.lastFrameDuration = MonoTime.currTime() - frameBeginTime;
            debug if (Globals.lastFrameDuration > Globals.frameDeadline) {
                log("Missed frame deadline of ", Globals.frameDeadline, 
                    "! Frame took ", Globals.lastFrameDuration, ".");
            }
        }

        ++frameNumber;
        glfwPollEvents();

        vkWaitForFences(logicalDevice, 1, &inFlightFences[Globals.currentFrame], VK_TRUE, ulong.max);

        uint imageIndex;
        vkAcquireNextImageKHR(logicalDevice, swapchain.swapchain, ulong.max, 
                              imageAvailableSemaphores[Globals.currentFrame], 
                              VK_NULL_HANDLE, &imageIndex);

        enforce(imageIndex < imagesInFlightFences.length);
        enforce(imageIndex < Globals.uniforms.length);
        enforce(imageIndex < swapchain.uniformBuffers.length);

        if (imagesInFlightFences[imageIndex] != VK_NULL_HANDLE) {
            auto fenceStatus = logicalDevice.vkGetFenceStatus(
                imagesInFlightFences[imageIndex]);

            if (fenceStatus == VK_NOT_READY) {
                debug log("Waiting for fence. (Frame ", frameNumber, ")");
            }
            
            vkWaitForFences(logicalDevice, 1, &imagesInFlightFences[imageIndex], 
                            VK_TRUE, ulong.max);
        }

        // Mark the image as being in use by this frame
        imagesInFlightFences[imageIndex] = inFlightFences[Globals.currentFrame];

        VkPipelineStageFlags[1] waitStages       = [VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT];
        VkSemaphore[1]          waitSemaphores   = [imageAvailableSemaphores[Globals.currentFrame]];
        VkSemaphore[1]          signalSemaphores = [renderFinishedSemaphores[Globals.currentFrame]];

        VkSubmitInfo submitInfo = {
            waitSemaphoreCount   : 1,
            pWaitSemaphores      : waitSemaphores.ptr,
            pWaitDstStageMask    : waitStages.ptr,
            commandBufferCount   : 1,
            pCommandBuffers      : &swapchain.commandBuffers[imageIndex],
            signalSemaphoreCount : 1,
            pSignalSemaphores    : signalSemaphores.ptr,
        };

        vkResetFences(logicalDevice, 1, &inFlightFences[Globals.currentFrame]);

        updateUniforms(logicalDevice, swapchain.uniformBuffers[imageIndex], imageIndex);

        import game;
        Game.tick();

        auto submitResult = vkQueueSubmit(graphicsQueue, 1, &submitInfo, 
                                          inFlightFences[Globals.currentFrame]);
                                        
        enforce(submitResult == VK_SUCCESS);

        VkSwapchainKHR[1] swapchains = [swapchain.swapchain];

        VkPresentInfoKHR presentInfo = {
            waitSemaphoreCount : 1,
            pWaitSemaphores    : signalSemaphores.ptr,
            swapchainCount     : 1,
            pSwapchains        : swapchains.ptr, 
            pImageIndices      : &imageIndex,
            pResults           : null,
        };

        auto queuePresentResult = vkQueuePresentKHR(presentQueue, &presentInfo);

        switch (queuePresentResult) {
            case VK_ERROR_OUT_OF_DATE_KHR: debug log("Out of date!"); break;
            case VK_SUBOPTIMAL_KHR: debug log("Suboptimal!"); break;
            default: break;
        }

        if (queuePresentResult == VK_ERROR_OUT_OF_DATE_KHR || 
            queuePresentResult == VK_SUBOPTIMAL_KHR || 
            Globals.framebufferWasResized) 
        {
            debug log("Recreating swapchain (frame ", frameNumber, ")");

            Globals.framebufferWasResized = false;

            swapchain = recreateSwapchain(
                logicalDevice, 
                physicalDevice, 
                surface, 
                Globals.window,
                vertexBuffer.buffer,
                pipelineLayout, 
                descriptorSetLayout,
                commandPool, 
                swapchain
            );

            auto extent = physicalDevice.getSurfaceExtent(surface, Globals.window);

            issueRenderCommands(
                swapchain, extent, pipelineLayout, vertices, vertexBuffer.buffer);

            Globals.uniforms.length = swapchain.imageViews.length;
        }

        Globals.currentFrame = 
            (Globals.currentFrame + 1) % MAX_FRAMES_IN_FLIGHT;
    } // End of main loop

    vkDeviceWaitIdle(logicalDevice);

    vulkanCleanup(instance, 
                  messenger,
                  surface, 
                  logicalDevice, 
                  [vertexBuffer],
                  descriptorSetLayout,
                  pipelineLayout, 
                  descriptorPool,
                  commandPool,
                  swapchain,
                  imageAvailableSemaphores ~ renderFinishedSemaphores, 
                  inFlightFences);
}