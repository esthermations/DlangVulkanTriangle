import std.stdio;
import std.exception;
import erupted;
import glfw3.api;

import util;
import globals;

/// How many frames in advance we should allow Vulkan to render.
enum MAX_FRAMES_IN_FLIGHT = 2;

void main() {

    import core.time;
    Globals.programT0 = MonoTime.currTime();

    glfwInit();
    scope (exit) glfwTerminate();

    enforce(glfwVulkanSupported(), "No Vulkan support from GLFW!");

    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE);

    auto window = glfwCreateWindow(800, 600, "Carl", null, null);
    scope (exit) glfwDestroyWindow(window);

    extern (C) 
    void fbResizeCallback(GLFWwindow *window, int width, int height) {
        Globals.framebufferWidth      = width;
        Globals.framebufferHeight     = height;
        Globals.framebufferWasResized = true;
    }

    glfwSetFramebufferSizeCallback(window, &fbResizeCallback);

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
        VK_KHR_SWAPCHAIN_EXTENSION_NAME
    ];

    import erupted.vulkan_lib_loader;

    bool vulkanLoadedOkay = loadGlobalLevelFunctions;
    enforce(vulkanLoadedOkay, "Failed to load Vulkan functions!");

    VkApplicationInfo appInfo = {
        pApplicationName : "Hello Triangle",
        apiVersion       : VK_MAKE_VERSION(1, 0, 2),
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

    const(char)*[] extensions;
    extensions.length = glfwExtensionCount + 1;

    for (auto i = 0; i < glfwExtensionCount; ++i) {
        extensions[i] = glfwExtensions[i];
    }

    extensions[$ - 1] = VK_EXT_DEBUG_UTILS_EXTENSION_NAME;

    VkInstanceCreateInfo instanceCreateInfo = {
        pApplicationInfo        : &appInfo, 
        enabledExtensionCount   : cast(uint) extensions.length, 
        ppEnabledExtensionNames : extensions.ptr,
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
            instance, window, null, cast(ulong*)&surface);
        enforce(!errors, "Failed to create a window surface!");
    }

    VkPhysicalDevice physicalDevice = 
        selectPhysicalDevice(instance, requiredDeviceExtensions, surface);

    // Create the device queue
    QueueFamilies queueFamilies = selectQueueFamilies(physicalDevice, surface);

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

    vkGetDeviceQueue(logicalDevice, queueFamilies.graphics.get, 0, &graphicsQueue);
    vkGetDeviceQueue(logicalDevice, queueFamilies.present.get, 0, &presentQueue);

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

    // Create vertex buffer

    Buffer vertexBuffer = createBuffer(
        logicalDevice, 
        physicalDevice,
        Globals.vertices.length * Vertex.sizeof,
        VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, 
        ( VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | 
          VK_MEMORY_PROPERTY_HOST_COHERENT_BIT )
    );

    // Create swapchain

    auto surfaceFormat = physicalDevice.getSurfaceFormat(surface);
    auto surfaceExtent = physicalDevice.getSurfaceExtent(surface, window);

    SwapchainWithDependents swapchain;

    swapchain.swapchain      = logicalDevice.createSwapchain(
        physicalDevice, surface, window);
    swapchain.imageViews     = logicalDevice.createImageViews(
        physicalDevice, surface, swapchain.swapchain, window);
    swapchain.uniformBuffers = logicalDevice.createUniformBuffers(
        physicalDevice, swapchain.imageViews.length);
    swapchain.renderPass     = logicalDevice.createRenderPass(
        surfaceFormat);
    swapchain.pipeline       = logicalDevice.createGraphicsPipeline(
        pipelineLayout, surfaceExtent, swapchain.renderPass);
    swapchain.framebuffers   = logicalDevice.createFramebuffers(
        swapchain.imageViews, swapchain.renderPass, surfaceExtent);
    swapchain.commandBuffers = logicalDevice.createCommandBuffers(
        swapchain.framebuffers, commandPool);
    swapchain.descriptorPool = logicalDevice.createDescriptorPool();
    swapchain.descriptorSets = logicalDevice.createDescriptorSets(
        swapchain.descriptorPool, descriptorSetLayout, swapchain.uniformBuffers);

    // Send data to the buffers

    sendDataToBuffer(logicalDevice, vertexBuffer, Globals.vertices.ptr);
    
    void updateUniforms(VkDevice logicalDevice, Buffer uniformBuffer, uint currentImage) 
        in (currentImage < Globals.uniforms.length)
    {
        MonoTime currentTime = MonoTime.currTime();

        import std.conv : to;
        auto duration = to!TickDuration(currentTime - Globals.programT0);
        const float timeAsFloat = core.time.to!("seconds", float)(duration);

        import gl3n.linalg;
        Globals.uniforms[currentImage].model = 
            mat4.identity.rotatez(timeAsFloat);

        sendDataToBuffer(
            logicalDevice, 
            uniformBuffer, 
            &Globals.uniforms[currentImage]
        );
    }

    // Record commands

    issueRenderCommands(
        swapchain, 
        surfaceExtent, 
        pipelineLayout, 
        swapchain.descriptorSets, 
        vertexBuffer.buffer
    );

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

    /*
    ---------------------------------------------------------------------------
    --  Main Loop
    ---------------------------------------------------------------------------
    */

    uint frameNumber = 0;

    while (!glfwWindowShouldClose(window)) {
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
                debug writeln("Waiting for fence. (Frame ", frameNumber, ")");
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

        auto submitResult = vkQueueSubmit(graphicsQueue, 1, &submitInfo, 
                                          inFlightFences[Globals.currentFrame]);
                                        
        enforce(submitResult == VK_SUCCESS);

        VkSwapchainKHR[] swapchains = [swapchain.swapchain];

        VkPresentInfoKHR presentInfo = {
            waitSemaphoreCount : 1,
            pWaitSemaphores    : signalSemaphores.ptr,
            swapchainCount     : 1,
            pSwapchains        : swapchains.ptr, 
            pImageIndices      : &imageIndex,
            pResults           : null,
        };

        auto queuePresentResult = vkQueuePresentKHR(presentQueue, &presentInfo);

        if (queuePresentResult == VK_ERROR_OUT_OF_DATE_KHR || 
            queuePresentResult == VK_SUBOPTIMAL_KHR || 
            Globals.framebufferWasResized) 
        {
            swapchain = recreateSwapchain(
                logicalDevice, 
                physicalDevice, 
                surface, 
                window,
                vertexBuffer.buffer,
                pipelineLayout, 
                descriptorSetLayout,
                commandPool, 
                swapchain
            );

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
                  [vertexBuffer] ~ swapchain.uniformBuffers,
                  descriptorSetLayout,
                  pipelineLayout, 
                  descriptorPool,
                  commandPool,
                  swapchain,
                  imageAvailableSemaphores ~ renderFinishedSemaphores, 
                  inFlightFences);
}

