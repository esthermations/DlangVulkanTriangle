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

    auto player      = Game.createEntity;
    auto camera      = Game.createEntity;
    auto theStranger = Game.createEntity;

    Game.position    [camera] = vec3(0.0, 5.up, 5.backwards);

    Game.position    [theStranger] = vec3(0);
    Game.velocity    [theStranger] = vec3(0);
    Game.acceleration[theStranger] = vec3(0);

    Game.position    [player] = vec3(0);
    Game.velocity    [player] = vec3(0);
    Game.acceleration[player] = vec3(0);

    Game.playerEntity = player;

    // Init GLFW

    glfwInit();
    scope (exit) glfwTerminate();

    enforce(glfwVulkanSupported(), "No Vulkan support from GLFW!");

    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE);

    Globals.window = glfwCreateWindow(
        Globals.framebufferWidth, 
        Globals.framebufferHeight, 
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

    renderer.init(
        appInfo, 
        requiredLayers, 
        requiredInstanceExtensions, 
        requiredDeviceExtensions,
    );

    // Import some 3D models

    import obj;

    Vertex[] vertices;

    {
        ObjData model = parseObj("./models/Barrel02.obj");
        vertices.length = model.positions.length;
        foreach (i; 0 .. vertices.length) {
            vertices[i].position = model.positions[i];
            vertices[i].normal   = model.normals[i];
        }
    }

    // Create vertex buffer using those vertices

    Buffer vertexBuffer = createBufferWithData(
        VK_BUFFER_USAGE_VERTEX_BUFFER_BIT, 
        ( VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT 
        | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT ),
        vertices,
    );

    // Record commands

    vertexBuffer.render();

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