import std.stdio;
import std.exception;
import erupted;
import glfw3.api;

import util;

/// How many frames in advance we should allow Vulkan to render.
enum MAX_FRAMES_IN_FLIGHT = 2;


struct Frame {
    struct Semaphores {
        VkSemaphore imageIsAvailable;
        VkSemaphore renderIsFinished;
    }

    Semaphores semaphores;
}

struct Globals {
    static ulong currentFrame; /// Latest frame? This might be named better.
    static Frame[MAX_FRAMES_IN_FLIGHT] frames;
}

void main() {

    glfwInit();
    scope (exit) glfwTerminate();

    enforce(glfwVulkanSupported(), "No Vulkan support from GLFW!");

    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);

    auto window = glfwCreateWindow(800, 600, "Vulkan", null, null);
    scope (exit) glfwDestroyWindow(window);

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

    VkResult createSurfaceResult = cast(erupted.VkResult) 
        glfwCreateWindowSurface(instance, window, null, cast(ulong*)&surface);
    enforce(createSurfaceResult == VK_SUCCESS, 
            "Failed to create a window surface!");

    VkPhysicalDevice physicalDevice = 
        selectPhysicalDevice(instance, requiredDeviceExtensions, surface);

    // Logical device
    VkDevice logicalDevice;

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

    auto logicalDeviceCreatedOkay = 
        vkCreateDevice(physicalDevice, &deviceCreateInfo, null, &logicalDevice);
    enforce(logicalDeviceCreatedOkay == VK_SUCCESS, 
            "Failed to create VkDevice!");

    loadDeviceLevelFunctions(logicalDevice);

    VkQueue graphicsQueue;
    VkQueue presentQueue;

    vkGetDeviceQueue(logicalDevice, queueFamilies.graphics.get, 0, &graphicsQueue);
    vkGetDeviceQueue(logicalDevice, queueFamilies.present.get, 0, &presentQueue);

    // Create swapchain

    VkSwapchainKHR swapchain = createSwapchain(logicalDevice, physicalDevice, surface, window);

    auto surfaceFormat = physicalDevice.getSurfaceFormat(surface);
    auto surfaceExtent = physicalDevice.getSurfaceExtent(surface, window);

    // Create image views

    VkImageView[] imageViews = createImageViews(
        logicalDevice, swapchain, window, swapchainImageFormat, swapchainExtent);

    // This is where uniforms would go
    VkPipelineLayout pipelineLayout;
    VkPipelineLayoutCreateInfo pipelineLayoutCreateInfo;

    auto pipelineLayoutCreateResult = 
        vkCreatePipelineLayout(logicalDevice, &pipelineLayoutCreateInfo, null, &pipelineLayout);

    enforce(pipelineLayoutCreateResult == VK_SUCCESS, 
            "Failed to create pipeline layout");


    // Create render pass

    auto renderPass = logicalDevice.createRenderPass(surfaceFormat);

    // Create graphics pipeline

    auto graphicsPipeline = createGraphicsPipeline(logicalDevice, swapchainExtent, renderPass);

    // Create framebuffers

    auto framebuffers = createFramebuffers(logicalDevice, imageViews, renderPass, swapchainExtent);

    // Command buffers

    VkCommandPool commandPool;

    VkCommandPoolCreateInfo commandPoolCreateInfo = {
        queueFamilyIndex : queueFamilies.graphics.get,
        flags            : 0,
    };

    auto createCommandPoolResult = vkCreateCommandPool(
        logicalDevice, &commandPoolCreateInfo, null, &commandPool);

    enforce(createCommandPoolResult == VK_SUCCESS, 
            "Failed to create command pool.");

    // Record commands

    VkClearValue clearColour = { 
        color : { 
            float32 : [0.0, 0.0, 0.0, 1.0] 
        },
    };

    foreach (i, commandBuffer; commandBuffers) {
        VkCommandBufferBeginInfo beginInfo;
        auto beginResult = vkBeginCommandBuffer(commandBuffer, &beginInfo);
        enforce(beginResult == VK_SUCCESS, "Failed to begin command buffer");

        // Start a render pass
        VkRenderPassBeginInfo info = {
            renderPass  : renderPass,
            framebuffer : swapchainFrameBuffers[i],
            renderArea  : {
                offset : {0, 0},
                extent : swapchainExtent,
            },
            clearValueCount : 1,
            pClearValues    : &clearColour,
        };
        
        commandBuffer.vkCmdBeginRenderPass(&info, VK_SUBPASS_CONTENTS_INLINE);
        commandBuffer.vkCmdBindPipeline(VK_PIPELINE_BIND_POINT_GRAPHICS, graphicsPipeline);
        commandBuffer.vkCmdDraw(3, 1, 0, 0);
        commandBuffer.vkCmdEndRenderPass();

        auto endResult = vkEndCommandBuffer(commandBuffer);
        enforce(endResult == VK_SUCCESS, "Failed to end command buffer.");
    }

    VkSemaphore[MAX_FRAMES_IN_FLIGHT] imageAvailableSemaphores;
    VkSemaphore[MAX_FRAMES_IN_FLIGHT] renderFinishedSemaphores;
    VkFence[MAX_FRAMES_IN_FLIGHT]     inFlightFences;
    VkFence[]                         imagesInFlightFences;
    imagesInFlightFences.length = swapchainImageViews.length;

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

    while (!glfwWindowShouldClose(window)) {
        glfwPollEvents();

        vkWaitForFences(logicalDevice, 1, &inFlightFences[Globals.currentFrame], VK_TRUE, ulong.max);

        uint imageIndex;
        vkAcquireNextImageKHR(logicalDevice, swapchain, ulong.max, 
                              imageAvailableSemaphores[Globals.currentFrame], 
                              VK_NULL_HANDLE, &imageIndex);

        if (imagesInFlightFences[imageIndex] != VK_NULL_HANDLE) {
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
            pCommandBuffers      : &commandBuffers[imageIndex],
            signalSemaphoreCount : 1,
            pSignalSemaphores    : signalSemaphores.ptr,
        };

        vkResetFences(logicalDevice, 1, &inFlightFences[Globals.currentFrame]);

        auto submitResult = vkQueueSubmit(graphicsQueue, 1, &submitInfo, 
                                          inFlightFences[Globals.currentFrame]);
        enforce(submitResult == VK_SUCCESS);

        VkSwapchainKHR[] swapchains = [swapchain];

        VkPresentInfoKHR presentInfo = {
            waitSemaphoreCount : 1,
            pWaitSemaphores    : signalSemaphores.ptr,
            swapchainCount     : 1,
            pSwapchains        : swapchains.ptr, 
            pImageIndices      : &imageIndex,
            pResults           : null,
        };

        vkQueuePresentKHR(presentQueue, &presentInfo);

        Globals.currentFrame = 
            (Globals.currentFrame + 1) % MAX_FRAMES_IN_FLIGHT;

        // HACK: avoiding sync issues by just waiting until the entire device is
        // idle before proceeding to the next frame.
        //vkQueueWaitIdle(presentQueue); 
    }

    vkDeviceWaitIdle(logicalDevice);

    vulkanCleanup(instance, 
                  messenger,
                  surface, 
                  logicalDevice, 
                  swapchain, 
                  swapchainImageViews, 
                  swapchainFrameBuffers, 
                  commandBuffers, 
                  commandPool, 
                  renderPass, 
                  graphicsPipeline, 
                  pipelineLayout, 
                  imageAvailableSemaphores ~ renderFinishedSemaphores, 
                  inFlightFences);
}

