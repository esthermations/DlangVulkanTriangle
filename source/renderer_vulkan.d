module renderer_vulkan;

import renderer_interface;

import std.stdio;
import std.exception : enforce;
import std.typecons : Nullable;
import std.experimental.logger;

import glfw3.api;
import gl3n.linalg;
import erupted;
import erupted.vulkan_lib_loader;

static import globals;
import game : Frame;

// Extension function pointers -- these need to be loaded before called
PFN_vkCreateDebugUtilsMessengerEXT  vkCreateDebugUtilsMessengerEXT;
PFN_vkDestroyDebugUtilsMessengerEXT vkDestroyDebugUtilsMessengerEXT;


final class VulkanRenderer : Renderer {

    /*
        State
    */

private:

    VkInstance       instance;
    VkSurfaceKHR     surface;
    VkPhysicalDevice physicalDevice;
    VkDevice         logicalDevice;
    VkQueue          graphicsQueue;
    VkQueue          presentQueue;
    //VkQueue transferQueue;

    VkDebugUtilsMessengerEXT debugMessenger;

    VkDescriptorSetLayout   descriptorSetLayout;
    VkPipelineLayout        pipelineLayout;
    VkCommandPool           commandPool;
    SwapchainWithDependents swapchain;

    size_t uniformDataSize;
    size_t vertexSize;

    /*
        Renderer interface implementation
    */

public:

    override void render(FrameId fid) {
        VkPipelineStageFlags waitStages = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;

        VkSubmitInfo submitInfo = {
            waitSemaphoreCount   : 1,
            // This semaphore should already be signalled because
            // acquireImageIndex waits for it.
            pWaitSemaphores      : &this.swapchain.imageAvailableSemaphores[fid],
            pWaitDstStageMask    : &waitStages,
            signalSemaphoreCount : 1,
            pSignalSemaphores    : &this.swapchain.renderFinishedSemaphores[fid],
            commandBufferCount   : 1,
            pCommandBuffers      : &this.swapchain.commandBuffers[fid],
        };

        {
            auto errors = vkQueueSubmit(
                this.graphicsQueue,
                1,
                &submitInfo,
                this.swapchain.commandBufferReadyFences[fid]
            );
            enforce(!errors);
        }

        VkPresentInfoKHR presentInfo = {
            waitSemaphoreCount : 1,
            pWaitSemaphores    : &this.swapchain.renderFinishedSemaphores[fid],
            swapchainCount     : 1,
            pSwapchains        : &this.swapchain.swapchain,
            pImageIndices      : &fid,
            pResults           : null,
        };

        // Present the queue, and handle window resizes if needed

        auto queuePresentResult = vkQueuePresentKHR(presentQueue, &presentInfo);

        debug switch (queuePresentResult) {
            case VK_ERROR_OUT_OF_DATE_KHR: log("Out of date!"); break;
            case VK_SUBOPTIMAL_KHR:        log("Suboptimal!");  break;
            default: break;
        }

        if (queuePresentResult == VK_ERROR_OUT_OF_DATE_KHR ||
            queuePresentResult == VK_SUBOPTIMAL_KHR ||
            globals.windowWasResized)
        {
            debug log("Recreating swapchain. FIXME: This may cause getFrameState() for other frames to return unexpected results.");
            globals.windowWasResized = false;
            this.swapchain = recreateSwapchainWithDependents!UniformDataT();
        }

        this.swapchain.frameState[fid] = Renderer.FrameState.SUBMITTED;
    }


    override void initWindow(string windowName, size_t uniformDataSize, size_t vertexSize) {

        this.uniformDataSize = uniformDataSize;
        this.vertexSize = vertexSize;

        // Load initial set of Vulkan functions

        {
            auto vulkanLoadedOkay = loadGlobalLevelFunctions;
            enforce(vulkanLoadedOkay, "Failed to load Vulkan functions!");
        }

        // Ensure we have required layers
        import std.string : toStringz;

        const(char)*[] requiredLayers = [
            "VK_LAYER_KHRONOS_validation".toStringz
        ];

        enforce(haveAllRequiredLayers(requiredLayers));
        debug log("We have all required extensions!");

        VkApplicationInfo appInfo = {
            pApplicationName : windowName.toStringz,
            apiVersion       : VK_MAKE_VERSION(1, 1, 0),
        };

        const(char)*[] requiredDeviceExtensions = [
            VK_KHR_SWAPCHAIN_EXTENSION_NAME,
            VK_KHR_MAINTENANCE1_EXTENSION_NAME
        ];

        const(char)*[] requiredInstanceExtensions = [
            VK_EXT_DEBUG_UTILS_EXTENSION_NAME,
        ];

        // Add glfw extensions

        {
            uint count;
            auto glfwExtensions = glfwGetRequiredInstanceExtensions(&count);

            foreach (i; 0 .. count) {
                requiredInstanceExtensions ~= glfwExtensions[i];
            }
        }

        // Create the instance

        {
            VkInstanceCreateInfo createInfo = {
                pApplicationInfo        : &appInfo,
                enabledExtensionCount   : cast(uint) requiredInstanceExtensions.length,
                ppEnabledExtensionNames : requiredInstanceExtensions.ptr,
                enabledLayerCount       : cast(uint) requiredLayers.length,
                ppEnabledLayerNames     : requiredLayers.ptr,
            };

            auto errors = vkCreateInstance(&createInfo, null, &this.instance);
            enforce(!errors, "Failed to create VkInstance!");
        }

        loadInstanceLevelFunctions(this.instance);
        debug log("Instance created, and instance-level functions loaded!");

        // Set up debug messenger

        this.debugMessenger = createDebugMessenger();

        // Create rendering surface

        {
            import glfw3.vulkan : glfwCreateWindowSurface;
            auto errors = cast(erupted.VkResult) glfwCreateWindowSurface(
                instance, globals.window, null, cast(ulong*)&this.surface);
            enforce(!errors, "Failed to create a window surface!");
        }

        // Select physical device

        this.physicalDevice = selectPhysicalDevice(requiredDeviceExtensions);

        // Create the logical device

        QueueFamilies queueFamilies = selectQueueFamilies(this.physicalDevice);
        enforce(queueFamilies.isComplete);

        {
            static float[1] queuePriorities = [1.0];

            VkDeviceQueueCreateInfo presentQueueCreateInfo = {
                queueFamilyIndex : queueFamilies.present.get,
                queueCount       : 1,
                pQueuePriorities : queuePriorities.ptr,
            };

            VkDeviceQueueCreateInfo graphicsQueueCreateInfo = {
                queueFamilyIndex : queueFamilies.graphics.get,
                queueCount       : 1,
                pQueuePriorities : queuePriorities.ptr,
            };

            VkDeviceQueueCreateInfo[] queueCreateInfos;

            queueCreateInfos ~= graphicsQueueCreateInfo;

            // Append presentFamily only if it's different to graphics family.
            if (queueFamilies.present.get != queueFamilies.graphics.get) {
                queueCreateInfos ~= presentQueueCreateInfo;
            }

            VkPhysicalDeviceFeatures deviceFeatures;

            VkDeviceCreateInfo createInfo = {
                pQueueCreateInfos       : queueCreateInfos.ptr,
                queueCreateInfoCount    : cast(uint) queueCreateInfos.length,
                pEnabledFeatures        : &deviceFeatures,
                enabledExtensionCount   : cast(uint) requiredDeviceExtensions.length,
                ppEnabledExtensionNames : requiredDeviceExtensions.ptr,
            };

            auto errors = vkCreateDevice(
                physicalDevice, &createInfo, null, &logicalDevice);
            enforce(!errors, "Failed to create VkDevice!");

        }

        // Load Vulkan functions for the VkDevice (via erupted)

        loadDeviceLevelFunctions(logicalDevice);
        debug log("Logical device created, and device-level functions loaded!");

        // Set queues for this device

        vkGetDeviceQueue(logicalDevice, queueFamilies.graphics.get, 0, &graphicsQueue);
        vkGetDeviceQueue(logicalDevice, queueFamilies.present.get, 0, &presentQueue);
        //vkGetDeviceQueue(logicalDevice, queueFamilies.transfer.get, 0, &transferQueue);

        // Create descriptor set layout

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

        // Create pipeline layout

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

        {
            VkCommandPoolCreateInfo createInfo = {
                queueFamilyIndex : queueFamilies.graphics.get,
                flags            : VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            };

            auto errors = vkCreateCommandPool(
                logicalDevice, &createInfo, null, &commandPool);
            enforce(!errors, "Failed to create command pool.");
        }

        // Create swapchain
        this.swapchain = createSwapchainWithDependents();
    }


    override bool rendererIsInitialised() const {
        return this.logicalDevice != VK_NULL_HANDLE
            && this.physicalDevice != VK_NULL_HANDLE
            && this.swapchain.isValid()
            ;
    }


    override uint numFrameIds() const {
        return this.swapchain.numImages();
    }


    override FrameId acquireNextFrameId() {
        static FrameId nextFid = 0;
        FrameId fid = nextFid;

        VkResult errors = vkAcquireNextImageKHR
            (this.logicalDevice,
             this.swapchain.swapchain,
             ulong.max, // timeout (ns)
             this.swapchain.imageAvailableSemaphores[nextFid],
             VK_NULL_HANDLE, // fence
             &fid
        );
        enforce(!errors);

        nextFid = (nextFid + 1) % this.numFrameIds();

        return fid;
    }


    override Buffer createVertexBuffer(size_t sizeInBytes) {
        VulkanVertexBuffer b;
        b.create(
            sizeInBytes,
            VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        );
        return b;
    }


    override void setData(FrameId fid, Buffer buf, ubyte[] data) {
        auto vkBuf = cast(VulkanBuffer) buf;

        void *dst;
        vkMapMemory(vkBuf.device, vkBuf.memory, 0, vkBuf.size, 0, &dst);
        {
            import core.stdc.string : memcpy;
            memcpy(dst, data.ptr, (data.length * DataT.sizeof));
        }
        vkUnmapMemory(vkBuf.device, vkBuf.memory);
    }


    override void drawVertexBuffer(FrameId fid, Buffer vbuf, uint numInstances) {
        VkBuffer    [1] buffers = [(cast(VulkanBuffer) vbuf).buffer];
        VkDeviceSize[1] offsets = [0];

        auto cb = this.outer.swapchain.commandBuffers[fid];
        vkCmdBindVertexBuffers(cb, 0, 1, buffers.ptr, offsets.ptr);
        vkCmdDraw             (cb, buffer.elementCount(), numInstances, 0, 0);
    }


    override FrameState getFrameState(FrameId fid) const {
        return swapchain.frameState[fid];
    }


    override void beginCommandsForFrame(FrameId fid, ubyte[] uniformData) {
        auto cb = this.swapchain.commandBuffers[fid];

        // Reset the command buffer, putting it in the Initial state
        vkResetCommandBuffer(cb, cast(VkCommandBufferResetFlags) 0);

        // Begin the command buffer, putting it in the Recording state
        VkCommandBufferBeginInfo beginInfo = {
            flags : VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };

        vkBeginCommandBuffer(cb, &beginInfo);

        // Update uniforms
        vkCmdUpdateBuffer(
            this.swapchain.commandBuffers[fid],
            this.swapchain.uniformBuffers[fid].buffer,
            0,
            uniformData.sizeof,
            uniformData.ptr
        );

        // Start a render pass
        VkRenderPassBeginInfo info = {
            renderPass  : this.swapchain.renderPass,
            framebuffer : this.swapchain.framebuffers[fid],
            renderArea  : {
                offset : {0, 0},
                extent : this.getSurfaceExtent(),
            },
            clearValueCount : cast(uint) globals.clearValues.length,
            pClearValues    : globals.clearValues.ptr,
        };

        vkCmdBeginRenderPass   (cb, &info, VK_SUBPASS_CONTENTS_INLINE);
        vkCmdBindPipeline      (cb, VK_PIPELINE_BIND_POINT_GRAPHICS,
                                this.swapchain.pipeline);
        vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_GRAPHICS,
                                this.pipelineLayout, 0, 1,
                                &this.swapchain.descriptorSets[fid], 0,
                                null);

        this.swapchain.isRecording[fid] = true;
    }


    override void endCommandsForFrame(FrameId fid) {
        auto cb = this.swapchain.commandBuffers[fid];
        vkCmdEndRenderPass(cb);
        auto errors = vkEndCommandBuffer(cb);
        enforce(!errors);
        this.swapchain.frameState[fid] = Renderer.FrameState.FINISHED_RECORDING;
    }


    override void awaitFrameCompletion(FrameId fid) {
        // Wait for the command buffer to be ready (signalled by vkQueueSubmit)
        vkWaitForFences(this.logicalDevice, 1, &this.swapchain.commandBufferReadyFences[fid], false, ulong.max);
        // Reset the fence for next time
        vkResetFences  (this.logicalDevice, 1, &this.swapchain.commandBufferReadyFences[fid]);
        this.swapchain.frameState[fid] = Renderer.FrameState.INITIAL;
    }

    /*
        Vulkan-specific utility functions
    */

private:


    VulkanBuffer createUniformBuffer(size_t sizeInBytes) {
        VulkanBuffer b;
        b.create(
            sizeInBytes,
            VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
        );
        return b;
    }



    /// Will our Vulkan instance support all the provided layers?
    bool haveAllRequiredLayers(const(char)*[] requiredLayers) {
        uint layerCount;
        vkEnumerateInstanceLayerProperties(&layerCount, null);
        enforce(layerCount > 0, "No layers available? This is weird.");

        VkLayerProperties[] availableLayers;
        availableLayers.length = layerCount;
        vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.ptr);

        uint numRequiredLayersFound = 0;

        foreach (requiredLayer; requiredLayers) {
            foreach (layer; availableLayers) {
                immutable string layerName = layer.layerName.idup;
                import core.stdc.string : strcmp;

                if (strcmp(requiredLayer, layerName.ptr) == 0) {
                    ++numRequiredLayersFound;
                    break;
                }
            }
        }

        return numRequiredLayersFound == requiredLayers.length;
    }


    VkDebugUtilsMessengerEXT createDebugMessenger() {
        extern (Windows) VkBool32
        debugCallback(VkDebugUtilsMessageSeverityFlagBitsEXT      messageSeverity,
                      VkDebugUtilsMessageTypeFlagsEXT             messageType,
                      const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData,
                      void*                                       pUserData)
                      nothrow @nogc
        {
            import core.stdc.stdio : printf, fflush, stdout;
            printf("Vulkan Spec Violation: %s\n", pCallbackData.pMessageIdName);
            printf(" -> %s\n", pCallbackData.pMessage);
            fflush(stdout);
            return VK_FALSE;
        }

        VkDebugUtilsMessengerCreateInfoEXT createInfo = {
            messageSeverity : VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
                              VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                              VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
            messageType     : VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT    |
                              VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
                              VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
            pfnUserCallback : &debugCallback,
            pUserData       : null,
        };

        vkCreateDebugUtilsMessengerEXT = cast(PFN_vkCreateDebugUtilsMessengerEXT)
            vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");
        vkDestroyDebugUtilsMessengerEXT = cast(PFN_vkDestroyDebugUtilsMessengerEXT)
            vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT");

        enforce(vkCreateDebugUtilsMessengerEXT !is null);
        enforce(vkDestroyDebugUtilsMessengerEXT !is null);

        VkDebugUtilsMessengerEXT ret;
        auto createErrors = vkCreateDebugUtilsMessengerEXT(
            this.instance, &createInfo, null, &ret);
        enforce(!createErrors, "Failed to create messenger!");

        return ret;
    }


    VkSwapchainKHR createSwapchain() {
        SwapchainSupportDetails support = querySwapchainSupport(this.physicalDevice);

        immutable surfaceFormat = selectSurfaceFormat(support.formats);
        immutable presentMode   = selectPresentMode(support.presentModes);
        immutable extent        = selectExtent(globals.window, support.capabilities);
        immutable imageCount    = support.capabilities.minImageCount;

        VkSwapchainCreateInfoKHR swapchainCreateInfo = {
            surface               : surface,
            minImageCount         : imageCount,
            imageFormat           : surfaceFormat.format,
            imageColorSpace       : surfaceFormat.colorSpace,
            imageExtent           : extent,
            imageArrayLayers      : 1,
            imageUsage            : VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            imageSharingMode      : VK_SHARING_MODE_EXCLUSIVE,
            queueFamilyIndexCount : 0,
            pQueueFamilyIndices   : null,
            preTransform          : support.capabilities.currentTransform,
            compositeAlpha        : VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            presentMode           : presentMode,
            clipped               : VK_TRUE,
            oldSwapchain          : VK_NULL_HANDLE,
        };

        VkSwapchainKHR swapchain;
        VkResult error = vkCreateSwapchainKHR(
            logicalDevice, &swapchainCreateInfo, null, &swapchain);
        enforce(!error, "Failed to create swapchain.");

        return swapchain;
    }


    VkImageView createImageView(VkDevice           logicalDevice,
                                VkImage            image,
                                VkFormat           format,
                                VkImageAspectFlags aspectMask) {
        VkImageViewCreateInfo createInfo = {
            image      : image,
            viewType   : VK_IMAGE_VIEW_TYPE_2D,
            format     : format,
            components : {
                r : VK_COMPONENT_SWIZZLE_IDENTITY,
                g : VK_COMPONENT_SWIZZLE_IDENTITY,
                b : VK_COMPONENT_SWIZZLE_IDENTITY,
                a : VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            subresourceRange : {
                aspectMask     : aspectMask,
                baseMipLevel   : 0,
                levelCount     : 1,
                baseArrayLayer : 0,
                layerCount     : 1,
            },
        };

        VkImageView ret;
        auto errors = vkCreateImageView(logicalDevice, &createInfo, null, &ret);
        enforce(!errors, "Failed to create an image view.");

        return ret;
    }


    VkImageView[] createImageViewsForSwapchain(VkSwapchainKHR swapchain) {
        // Images

        uint numImages;
        VkImage[] images;

        vkGetSwapchainImagesKHR(logicalDevice, swapchain, &numImages, null);
        images.length = numImages;
        vkGetSwapchainImagesKHR(logicalDevice, swapchain, &numImages, images.ptr);

        auto support = querySwapchainSupport(this.physicalDevice);
        auto format  = selectSurfaceFormat(support.formats).format;

        // Image views

        VkImageView[] ret;
        ret.length = images.length;

        foreach(i, image; images) {
            ret[i] = createImageView(
                logicalDevice, image, format, VK_IMAGE_ASPECT_COLOR_BIT);
        }

        return ret;
    }


    // TODO: Call this something better. It's all the Vulkan state that needs
    // to change when the window is resized.
    struct SwapchainWithDependents {
        VkSwapchainKHR    swapchain;
        VkRenderPass      renderPass;
        VkDescriptorPool  descriptorPool;
        DepthResources    depthResources;
        VkPipeline        pipeline;

        // Per-image (per-frame) data
        VkImageView             []imageViews;
        VkFramebuffer           []framebuffers;
        VkDescriptorSet         []descriptorSets;
        VulkanBuffer            []uniformBuffers;
        VkCommandBuffer         []commandBuffers;

        /// Signalled when the commandBuffer for this image can be submitted
        VkSemaphore             []imageAvailableSemaphores;
        /// Signalled when this frame has been submitted to be presented
        VkSemaphore             []renderFinishedSemaphores;
        /// Signalled when the command buffer can be re-used
        VkFence                 []commandBufferReadyFences;

        Renderer.FrameState     []frameState;

        invariant {
            assert(imageViews.length == framebuffers.length);
            assert(imageViews.length == descriptorSets.length);
            assert(imageViews.length == uniformBuffers.length);
            assert(imageViews.length == commandBuffers.length);
            assert(imageViews.length == imageAvailableSemaphores.length);
            assert(imageViews.length == renderFinishedSemaphores.length);
            assert(imageViews.length == commandBufferReadyFences.length);
            assert(imageViews.length == frameState.length);
        }


        uint numImages() const {
            return cast(uint) imageViews.length;
        }


        bool isValid() const {
            // There may be a bit more to it than this, but it's a good start.
            // Maybe ensure that every handle is unique?
            import std.algorithm : all, uniq, equal;
            return imageViews               .all!(h => h != VK_NULL_HANDLE)
                && descriptorSets           .all!(h => h != VK_NULL_HANDLE)
                && framebuffers             .all!(h => h != VK_NULL_HANDLE)
                && descriptorSets           .all!(h => h != VK_NULL_HANDLE)
                && commandBuffers           .all!(h => h != VK_NULL_HANDLE)
                && imageAvailableSemaphores .all!(h => h != VK_NULL_HANDLE)
                && renderFinishedSemaphores .all!(h => h != VK_NULL_HANDLE)
                && commandBufferReadyFences .all!(h => h != VK_NULL_HANDLE)
                ;
        }

    }


    SwapchainWithDependents createSwapchainWithDependents(UniformDataT)() {
        SwapchainWithDependents ret;

        vkDeviceWaitIdle(logicalDevice);

        const colourFormat = getSurfaceFormat();
        const depthFormat  = getDepthFormat();
        const extent       = getSurfaceExtent();

        ret.swapchain      = this.createSwapchain();
        ret.imageViews     = this.createImageViewsForSwapchain(ret.swapchain);

        uint numImages = cast(uint) ret.imageViews.length;

        ret.renderPass               = this.createRenderPass      (colourFormat, depthFormat);
        ret.pipeline                 = this.createGraphicsPipeline(ret.renderPass);
        ret.depthResources           = this.createDepthResources  ();
        ret.framebuffers             = this.createFramebuffers    (ret.imageViews, ret.depthResources.imageView, ret.renderPass);
        ret.uniformBuffers           = this.createUniformBuffers  (numImages, this.uniformDataSize);
        ret.descriptorPool           = this.createDescriptorPool  (numImages);
        ret.descriptorSets           = this.createDescriptorSets  (numImages, ret.descriptorPool, this.descriptorSetLayout, ret.uniformBuffers);
        ret.commandBuffers           = this.createCommandBuffers  (numImages);
        ret.imageAvailableSemaphores = this.createSemaphores      (numImages);
        ret.renderFinishedSemaphores = this.createSemaphores      (numImages);
        ret.commandBufferReadyFences = this.createFences          (numImages);
        ret.frameState[]             = Renderer.FrameState.INITIAL;

        return ret;
    }


    /// Clean up a SwapchainWithDependents. The commandPool and pipelineLayout
    /// are NOT destroyed.
    void cleanupSwapchainWithDependents() {
        vkDeviceWaitIdle(logicalDevice);

        foreach (framebuffer; this.swapchain.framebuffers) {
            vkDestroyFramebuffer(this.logicalDevice, framebuffer, null);
        }

        vkFreeCommandBuffers(this.logicalDevice, this.commandPool, this.swapchain.numImages(), this.swapchain.commandBuffers.ptr);

        foreach (i; 0 .. this.swapchain.numImages()) {
            vkDestroySemaphore(this.logicalDevice, this.swapchain.imageAvailableSemaphores[i], null);
            vkDestroySemaphore(this.logicalDevice, this.swapchain.renderFinishedSemaphores[i], null);
            vkDestroyFence    (this.logicalDevice, this.swapchain.commandBufferReadyFences[i], null);
        }

        vkDestroyPipeline(this.logicalDevice, this.swapchain.pipeline, null);

        vkDestroyRenderPass(
            this.logicalDevice, this.swapchain.renderPass, null);

        foreach (view; this.swapchain.imageViews) {
            vkDestroyImageView(this.logicalDevice, view, null);
        }

        vkDestroyImageView(
            this.logicalDevice, this.swapchain.depthResources.imageView, null);
        vkDestroyImage(
            this.logicalDevice, this.swapchain.depthResources.image, null);
        vkFreeMemory(
            this.logicalDevice, this.swapchain.depthResources.memory, null);

        foreach (buf; this.swapchain.uniformBuffers) {
            vkDestroyBuffer(this.logicalDevice, buf.buffer, null);
            vkFreeMemory   (this.logicalDevice, buf.memory, null);
        }

        vkFreeDescriptorSets(
            this.logicalDevice,
            this.swapchain.descriptorPool,
            cast(uint) this.swapchain.descriptorSets.length,
            this.swapchain.descriptorSets.ptr
        );

        vkDestroyDescriptorPool(this.logicalDevice, this.swapchain.descriptorPool, null);

        vkDestroySwapchainKHR(
            this.logicalDevice, this.swapchain.swapchain, null);
    }


    SwapchainWithDependents recreateSwapchainWithDependents(UniformDataT)() {
        vkDeviceWaitIdle(this.logicalDevice);
        this.cleanupSwapchainWithDependents();
        return createSwapchainWithDependents!UniformDataT();
    }


    VkFence[] createFences(uint count, VkFenceCreateFlags flags = 0) {
        VkFence[] ret;
        ret.length = count;
        foreach (i; 0 .. count) {
            ret[i] = createFence(flags);
        }
        return ret;
    }


    VkFence createFence(VkFenceCreateFlags flags = 0) {
        VkFence ret;
        VkFenceCreateInfo info = { flags : flags };
        auto errors = vkCreateFence(this.logicalDevice, &info, null, &ret);
        enforce(!errors);
        return ret;
    }


    /// Create the given number of semaphores using the Renderer's logical
    /// device
    VkSemaphore[] createSemaphores(uint count) {
        VkSemaphore[] ret;
        ret.length = count;
        foreach (i; 0 .. count) {
            ret[i] = createSemaphore();
        }
        return ret;
    }


    VkSemaphore createSemaphore() {
        VkSemaphore ret;
        VkSemaphoreCreateInfo info;
        auto errors = vkCreateSemaphore(this.logicalDevice, &info, null, &ret);
        enforce(!errors);
        return ret;
    }


    /// Create the given number of command buffers using the Renderer's current
    /// command pool.
    VkCommandBuffer[] createCommandBuffers(uint count) {
        VkCommandBuffer[] ret;
        ret.length = count;

        VkCommandBufferAllocateInfo allocateInfo = {
            commandPool        : commandPool,
            level              : VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            commandBufferCount : count,
        };

        auto errors =
            vkAllocateCommandBuffers(this.logicalDevice, &allocateInfo, ret.ptr);
        enforce(!errors, "Failed to create Command Buffers");

        return ret;
    }


    /// Create a framebuffer for each provided vkImageView.
    VkFramebuffer[] createFramebuffers(VkImageView[] imageViews,
                                       VkImageView   depthImageView,
                                       VkRenderPass  renderPass) {
        VkFramebuffer[] ret;
        ret.length = imageViews.length;

        auto extent = getSurfaceExtent();

        foreach (i, view; imageViews) {
            VkImageView[2] attachments = [ view, depthImageView ];

            VkFramebufferCreateInfo createInfo = {
                renderPass      : renderPass,
                attachmentCount : cast(uint) attachments.length,
                pAttachments    : attachments.ptr,
                width           : extent.width,
                height          : extent.height,
                layers          : 1,
            };

            auto errors =
                vkCreateFramebuffer(this.logicalDevice, &createInfo, null, &ret[i]);
            enforce(!errors, "Failed to create a framebuffer.");
        }

        return ret;
    }


    VkExtent2D getSurfaceExtent() {
        const support = querySwapchainSupport(this.physicalDevice);
        return selectExtent(globals.window, support.capabilities);
    }


    /// Set up the graphics pipeline for our application. There are a lot of
    /// hardcoded properties about our pipeline in this function -- it's not
    /// nearly as agnostic as it may appear.
    VkPipeline createGraphicsPipeline(VkRenderPass renderPass) {
        VkShaderModule vertModule = createShaderModule(logicalDevice, "./source/vert.spv");
        VkShaderModule fragModule = createShaderModule(logicalDevice, "./source/frag.spv");

        VkPipelineShaderStageCreateInfo vertStageCreateInfo = {
            stage  : VK_SHADER_STAGE_VERTEX_BIT,
            Module : vertModule,
            pName  : "main",
        };

        VkPipelineShaderStageCreateInfo fragStageCreateInfo = {
            stage  : VK_SHADER_STAGE_FRAGMENT_BIT,
            Module : fragModule,
            pName  : "main",
        };

        auto  bindingDescription    = getVertexBindingDescription();
        const attributeDescriptions = getVertexAttributeDescription();

        VkPipelineVertexInputStateCreateInfo vertexInputCreateInfo = {
            vertexBindingDescriptionCount   : 1,
            pVertexBindingDescriptions      : &bindingDescription,
            vertexAttributeDescriptionCount : cast(uint) attributeDescriptions.length,
            pVertexAttributeDescriptions    : attributeDescriptions.ptr,
        };

        VkPipelineInputAssemblyStateCreateInfo inputAssemblyCreateInfo = {
            topology               : VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            primitiveRestartEnable : VK_FALSE,
        };

        const extent = getSurfaceExtent();

        // NOTE that our viewport is flipped upside-down so we can use Y-up,
        // where Vulkan normally uses Y-down.
        VkViewport viewport = {
            x        : 0.0f,
            y        : extent.height,
            width    : extent.width,
            height   : -1.0f * extent.height,
            minDepth : 0.0f,
            maxDepth : 1.0f,
        };

        VkRect2D scissor = {
            offset : {0, 0},
            extent : extent,
        };

        VkPipelineViewportStateCreateInfo viewportStateCreateInfo = {
            viewportCount : 1,
            pViewports    : &viewport,
            scissorCount  : 1,
            pScissors     : &scissor,
        };

        VkPipelineRasterizationStateCreateInfo rasterisationStateCreateInfo = {
            depthClampEnable        : VK_FALSE,
            rasterizerDiscardEnable : VK_FALSE,
            polygonMode             : VK_POLYGON_MODE_FILL,
            lineWidth               : 1.0f,
            cullMode                : VK_CULL_MODE_BACK_BIT,
            frontFace               : VK_FRONT_FACE_COUNTER_CLOCKWISE,
            depthBiasEnable         : VK_FALSE,
            depthBiasClamp          : 0.0f,
        };

        VkPipelineMultisampleStateCreateInfo multisampleStateCreateInfo = {
            sampleShadingEnable : VK_FALSE,
            rasterizationSamples : VK_SAMPLE_COUNT_1_BIT,
        };

        VkPipelineColorBlendAttachmentState colourBlendAttachment = {
            colorWriteMask : VK_COLOR_COMPONENT_R_BIT |
                             VK_COLOR_COMPONENT_G_BIT |
                             VK_COLOR_COMPONENT_B_BIT |
                             VK_COLOR_COMPONENT_A_BIT,
            blendEnable    : VK_FALSE,
        };

        VkPipelineColorBlendStateCreateInfo colourBlendStateCreateInfo = {
            logicOpEnable   : VK_FALSE,
            attachmentCount : 1,
            pAttachments    : &colourBlendAttachment,
        };

        VkPipelineDepthStencilStateCreateInfo depthStencilStateCreateInfo = {
            depthTestEnable       : VK_TRUE,
            depthWriteEnable      : VK_TRUE,
            depthCompareOp        : VK_COMPARE_OP_LESS,
            depthBoundsTestEnable : VK_FALSE,
            stencilTestEnable     : VK_FALSE,
        };

        VkPipelineShaderStageCreateInfo[2] shaderStages =
            [vertStageCreateInfo, fragStageCreateInfo];

        VkGraphicsPipelineCreateInfo createInfo = {
            stageCount          : cast(uint) shaderStages.length,
            pStages             : shaderStages.ptr,
            pVertexInputState   : &vertexInputCreateInfo,
            pInputAssemblyState : &inputAssemblyCreateInfo,
            pViewportState      : &viewportStateCreateInfo,
            pRasterizationState : &rasterisationStateCreateInfo,
            pMultisampleState   : &multisampleStateCreateInfo,
            pDepthStencilState  : &depthStencilStateCreateInfo,
            pColorBlendState    : &colourBlendStateCreateInfo,
            pDynamicState       : null,
            layout              : pipelineLayout,
            renderPass          : renderPass,
            subpass             : 0,
        };

        VkPipeline ret;

        auto errors = vkCreateGraphicsPipelines(
            logicalDevice, VK_NULL_HANDLE, 1, &createInfo, null, &ret);
        enforce(!errors, "Failed to create graphics pipeline.");

        vkDestroyShaderModule(logicalDevice, fragModule, null);
        vkDestroyShaderModule(logicalDevice, vertModule, null);

        return ret;
    }


    // FIXME this should probably return a VkSurfaceFormatKHR.
    VkFormat getSurfaceFormat() {
        return selectSurfaceFormat(querySwapchainSupport(this.physicalDevice).formats).format;
    }


    VkRenderPass createRenderPass(VkFormat colourFormat, VkFormat depthFormat) {
        VkAttachmentDescription colourAttachment = {
            flags          : 0,
            format         : colourFormat,
            samples        : VK_SAMPLE_COUNT_1_BIT,
            loadOp         : VK_ATTACHMENT_LOAD_OP_CLEAR,
            storeOp        : VK_ATTACHMENT_STORE_OP_STORE,
            stencilLoadOp  : VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            stencilStoreOp : VK_ATTACHMENT_STORE_OP_DONT_CARE,
            initialLayout  : VK_IMAGE_LAYOUT_UNDEFINED,
            finalLayout    : VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        };

        VkAttachmentReference colourAttachmentReference = {
            attachment : 0,
            layout     : VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        };

        debug log("Depth format is ", depthFormat);

        VkAttachmentDescription depthAttachment = {
            format         : depthFormat,
            samples        : VK_SAMPLE_COUNT_1_BIT,
            loadOp         : VK_ATTACHMENT_LOAD_OP_CLEAR,
            storeOp        : VK_ATTACHMENT_STORE_OP_DONT_CARE,
            stencilLoadOp  : VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            stencilStoreOp : VK_ATTACHMENT_STORE_OP_DONT_CARE,
            initialLayout  : VK_IMAGE_LAYOUT_UNDEFINED,
            finalLayout    : VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        };

        VkAttachmentReference depthAttachmentReference = {
            attachment : 1,
            layout     : VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        };

        VkSubpassDescription subpass = {
            pipelineBindPoint       : VK_PIPELINE_BIND_POINT_GRAPHICS,
            colorAttachmentCount    : 1,
            pColorAttachments       : &colourAttachmentReference,
            pDepthStencilAttachment : &depthAttachmentReference,
        };

        VkSubpassDependency dependency = {
            srcSubpass    : VK_SUBPASS_EXTERNAL,
            dstSubpass    : 0,
            srcStageMask  : VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                            VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            srcAccessMask : 0,
            dstStageMask  : VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                            VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT,
            dstAccessMask : VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT |
                            VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        };

        auto attachments = [colourAttachment, depthAttachment];

        VkRenderPassCreateInfo createInfo = {
            attachmentCount : cast(uint) attachments.length,
            pAttachments    : attachments.ptr,
            subpassCount    : 1,
            pSubpasses      : &subpass,
            dependencyCount : 1,
            pDependencies   : &dependency,
        };

        VkRenderPass ret;
        auto errors = vkCreateRenderPass(logicalDevice, &createInfo, null, &ret);
        enforce(!errors, "Failed to create a render pass.");

        return ret;
    }


    struct QueueFamilies {
        Nullable!uint graphics;
        Nullable!uint present;
        Nullable!uint transfer;

        /// Are all queue families available?
        bool isComplete() {
            return !graphics.isNull && !present.isNull;
        }
    }


    /**
        Select queue families that meet our criteria, defined in this function.
        The members of QueueFamilies are nullable -- this function may fail to
        find all the queue families in that struct. If it can't find them, they
        will be null.
    */
    QueueFamilies selectQueueFamilies(VkPhysicalDevice particularPhysicalDevice) {
        VkQueueFamilyProperties[] queueFamilies;
        uint queueFamilyCount;
        vkGetPhysicalDeviceQueueFamilyProperties(particularPhysicalDevice,
                                                 &queueFamilyCount,
                                                 null);
        queueFamilies.length = queueFamilyCount;
        vkGetPhysicalDeviceQueueFamilyProperties(particularPhysicalDevice,
                                                 &queueFamilyCount,
                                                 queueFamilies.ptr);

        QueueFamilies ret;

        // debug log("Queue families: ", queueFamilies);

        foreach (i, family; queueFamilies) {
            auto supportsGraphics = family.queueFlags & VK_QUEUE_GRAPHICS_BIT;

            if (supportsGraphics) {
                ret.graphics = cast(uint) i;
            }

            VkBool32 supportsPresent = false;
            vkGetPhysicalDeviceSurfaceSupportKHR(particularPhysicalDevice,
                                                 cast(uint) i,
                                                 surface,
                                                 &supportsPresent);

            // NOTE: We may want to use different queue families for graphics
            // and present. Not sure why, but the tutorial said we would.
            if (supportsPresent) {
                ret.present = cast(uint) i;
            }

            auto supportsTransfer =
                (family.queueFlags & VK_QUEUE_TRANSFER_BIT) &&
                !(family.queueFlags & VK_QUEUE_GRAPHICS_BIT);

            if (supportsTransfer) {
                ret.transfer = cast(uint) i;
            }

            if (ret.isComplete) {
                //debug log("Using queues ", ret);
                return ret;
            }
        }

        enforce(ret.isComplete, "Failed to find suitable queue families.");
        return ret;
    }


    /// Is this device suitable for our purposes?
    bool isSuitable(VkPhysicalDevice particularPhysicalDevice,
                    const(char)*[]   requiredDeviceExtensions) {
        // Confirm device is a discrete GPU
        VkPhysicalDeviceProperties deviceProperties;
        vkGetPhysicalDeviceProperties(particularPhysicalDevice, &deviceProperties);

        if (deviceProperties.deviceType != VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
            return false;
        }

        // Confirm device supports our desired queue families
        QueueFamilies families = selectQueueFamilies(particularPhysicalDevice);
        if (!families.isComplete) {
            return false;
        }

        // Confirm device supports our desired device extensions
        uint numExtensions;
        vkEnumerateDeviceExtensionProperties(
            particularPhysicalDevice, null, &numExtensions, null);

        VkExtensionProperties[] availableDeviceExtensions;
        availableDeviceExtensions.length = numExtensions;
        vkEnumerateDeviceExtensionProperties(particularPhysicalDevice,
                                             null,
                                             &numExtensions,
                                             availableDeviceExtensions.ptr);


        // FIXME: this is an enormous nightmare because extension names are
        // char[256] and some things are const(char)* and some things are
        // string. That's all.

        import std.string : fromStringz;
        bool[string] extensionFound;

        foreach (ext; requiredDeviceExtensions) {
            extensionFound[ext.fromStringz] = false;
        }

        foreach (ext; availableDeviceExtensions) {
            auto name = ext.extensionName.ptr.fromStringz;

            if (name in extensionFound) {
                extensionFound[name.idup] = true;
            }
        }

        bool allExtensionsSupported = true;

        foreach (ext; requiredDeviceExtensions) {
            if (!extensionFound[ext.fromStringz]) {
                allExtensionsSupported = false;
            }
        }

        if (!allExtensionsSupported) {
            return false;
        }

        // Confirm swapchain support
        bool swapchainSuitable;

        SwapchainSupportDetails swapchainSupport = querySwapchainSupport(particularPhysicalDevice);
        swapchainSuitable = swapchainSupport.formats.length      != 0 &&
                            swapchainSupport.presentModes.length != 0;

        if (!swapchainSuitable) {
            return false;
        }

        return true;
    }


    /// Select a physical device available in the instance based on whether it
    /// satisfies isSuitable().
    VkPhysicalDevice selectPhysicalDevice(const(char)*[] requiredDeviceExtensions) {
        uint numPhysicalDevices;
        vkEnumeratePhysicalDevices(this.instance, &numPhysicalDevices, null);
        enforce(numPhysicalDevices > 0, "Couldn't find any devices!!");

        VkPhysicalDevice[] physicalDevices;
        physicalDevices.length = numPhysicalDevices;
        vkEnumeratePhysicalDevices(this.instance, &numPhysicalDevices,
                                   physicalDevices.ptr);

        foreach (physicalDevice; physicalDevices) {
            debug log("Got here");
            if (isSuitable(physicalDevice, requiredDeviceExtensions)) {
                return physicalDevice;
            }
        }

        enforce(false, "Couldn't find a suitable physical device!");
        return VK_NULL_HANDLE;
    }


    struct SwapchainSupportDetails {
        VkSurfaceCapabilitiesKHR   capabilities;
        VkSurfaceFormatKHR       []formats;
        VkPresentModeKHR         []presentModes;
    }


    SwapchainSupportDetails querySwapchainSupport(VkPhysicalDevice particularPhysicalDevice) {
        SwapchainSupportDetails ret;

        vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
            particularPhysicalDevice, this.surface, &ret.capabilities);

        debug logf("Our swapchain has %s images", ret.capabilities.maxImageCount);

        uint numFormats;
        vkGetPhysicalDeviceSurfaceFormatsKHR(
            particularPhysicalDevice, this.surface, &numFormats, null);
        ret.formats.length = numFormats;
        vkGetPhysicalDeviceSurfaceFormatsKHR(
            particularPhysicalDevice, this.surface, &numFormats, ret.formats.ptr);

        uint numPresentModes;
        vkGetPhysicalDeviceSurfacePresentModesKHR(
            particularPhysicalDevice, this.surface, &numPresentModes, null);
        ret.presentModes.length = numPresentModes;
        vkGetPhysicalDeviceSurfacePresentModesKHR(
            particularPhysicalDevice,
            this.surface,
            &numPresentModes,
            ret.presentModes.ptr
        );

        return ret;
    }


    VkSurfaceFormatKHR selectSurfaceFormat(in VkSurfaceFormatKHR[] formats)
        in (formats.length != 0)
    {
        foreach (format; formats) {
            if (format.format == VK_FORMAT_B8G8R8_SRGB &&
                format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
            {
                return format;
            }
        }

        return formats[0];
    }


    VkPresentModeKHR selectPresentMode(VkPresentModeKHR[] presentModes) {
        foreach (presentMode; presentModes) {
            // Triple-buffered. Might prefer IMMEDIATE for non-vsync.
            if (presentMode == VK_PRESENT_MODE_MAILBOX_KHR) {
                return presentMode;
            }
        }

        // Fallback case -- FIFO is guaranteed to be available
        return VK_PRESENT_MODE_FIFO_KHR;
    }


    VkExtent2D selectExtent(   GLFWwindow              *window,
                            in VkSurfaceCapabilitiesKHR capabilities) {

        // If width/height are set to 0xFFFFFFFF (UINT32_MAX) then the swapchain
        // gets to set the size of the extent (vkspec page 1153).

        if (capabilities.currentExtent.width != 0xFFFFFFFF) {
            // We're required to use the provided extent
            return capabilities.currentExtent;
        } else {
            // We get to choose the size of the surface, so we use the closest to
            // the size of the window as is valid.
            debug log("We're doing the surface extent translation thing.");

            int width, height;
            glfwGetFramebufferSize(window, &width, &height);

            import std.algorithm : clamp;

            immutable minWidth  = capabilities.minImageExtent.width;
            immutable maxWidth  = capabilities.maxImageExtent.width;
            immutable minHeight = capabilities.minImageExtent.height;
            immutable maxHeight = capabilities.maxImageExtent.height;

            VkExtent2D ret = {
                width  : cast(uint) clamp(width, minWidth, maxWidth),
                height : cast(uint) clamp(height, minHeight, maxHeight),
            };

            return ret;
        }
    }


    VkShaderModule createShaderModule(VkDevice logicalDevice, string path) {
        import std.stdio : File;
        auto file = File(path, "rb");
        auto data = file.rawRead(new uint[file.size / uint.sizeof]);

        VkShaderModuleCreateInfo createInfo = {
            codeSize : data.length * uint.sizeof,
            pCode    : data.ptr,
        };

        VkShaderModule ret;
        auto createResult =
            vkCreateShaderModule(logicalDevice, &createInfo, null, &ret);
        enforce(createResult == VK_SUCCESS, "Failed to create shader module");

        return ret;
    }


    class VulkanBuffer : Buffer {

        VkDevice       device;
        VkBuffer       buffer;
        VkDeviceMemory memory;
        size_t         size; /// The size in bytes of the buffer's storage

        void create(size_t sizeInBytes,
                    VkBufferUsageFlags bufferUsage,
                    VkMemoryPropertyFlags memoryProperties)
        {
            Buffer!T ret;
            ret.size = numElements * T.sizeof;

            // Create ret.buffer

            {
                VkBufferCreateInfo createInfo = {
                    size        : ret.size,
                    usage       : bufferUsage,
                    sharingMode : VK_SHARING_MODE_EXCLUSIVE,
                };

                auto errors = vkCreateBuffer(
                    this.logicalDevice, &createInfo, null, &ret.buffer);
                enforce(!errors, "Failed to create buffer!");
            }

            // Create ret.memory

            VkMemoryRequirements memRequirements;
            vkGetBufferMemoryRequirements(this.logicalDevice, ret.buffer, &memRequirements);

            VkMemoryAllocateInfo allocInfo = {
                allocationSize  : memRequirements.size,
                memoryTypeIndex : findMemoryType(memRequirements.memoryTypeBits,
                                                 memoryProperties),
            };

            {
                auto errors = vkAllocateMemory(
                    this.logicalDevice, &allocInfo, null, &ret.memory);
                enforce(!errors, "Failed to allocate buffer!");
            }

            {
                auto errors = vkBindBufferMemory(
                    this.logicalDevice, ret.buffer, ret.memory, 0);
                enforce(!errors, "Failed to bind buffer");
            }

            return ret;
        }


        /// Utility - how many elements are in this buffer assuming it contains
        /// ElementT?
        uint elementCount(ElementT)() const {
            return sizeInBytes() /  ElementT.sizeof;
        }


        override uint sizeInBytes() const {
            return cast(uint) this.size;
        }


        ~this() {
            vkDestroyBuffer(this.device, this.buffer, null);
            vkFreeMemory   (this.device, this.memory, null);
        }
    }


    /// Select a memory type that satisfies the requested properties.
    /// TODO: wtf does this actually do lmao document this better
    uint findMemoryType(uint typeFilter, VkMemoryPropertyFlags requestedProperties) {
        VkPhysicalDeviceMemoryProperties memProperties;
        vkGetPhysicalDeviceMemoryProperties(this.physicalDevice, &memProperties);

        foreach (uint i; 0 .. memProperties.memoryTypeCount) {
            immutable matchesFilter = typeFilter & (1 << i);
            immutable allPropertiesAvailable = (
                memProperties.memoryTypes[i].propertyFlags &
                requestedProperties
            );

            if (matchesFilter && allPropertiesAvailable) {
                return i;
            }
        }

        enforce(false, "Failed to find a suitable memory type!");
        return 0;
    }


    VkDescriptorPool createDescriptorPool(uint numDescriptors) {
        VkDescriptorPoolSize poolSize = {
            descriptorCount : numDescriptors,
        };

        VkDescriptorPoolCreateInfo createInfo = {
            poolSizeCount : 1,
            pPoolSizes    : &poolSize,
            maxSets       : numDescriptors,
            flags         : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
        };

        VkDescriptorPool ret;

        auto errors = vkCreateDescriptorPool(
            this.logicalDevice, &createInfo, null, &ret);
        enforce(!errors, "Failed to create a descriptor pool");

        return ret;
    }


    struct DepthResources {
        VkImage        image;
        VkImageView    imageView;
        VkDeviceMemory memory;
    }


    VkFormat getDepthFormat() {
        return VK_FORMAT_D16_UNORM;
    }


    DepthResources createDepthResources() {
        VkExtent2D extent = this.getSurfaceExtent();
        auto imageFormat = this.getDepthFormat();

        VkImageCreateInfo createInfo = {
            imageType     : VK_IMAGE_TYPE_2D,
            extent        : { width: extent.width, height: extent.height, depth: 1},
            mipLevels     : 1,
            arrayLayers   : 1,
            format        : imageFormat,
            tiling        : VK_IMAGE_TILING_OPTIMAL,
            initialLayout : VK_IMAGE_LAYOUT_UNDEFINED,
            usage         : VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
            samples       : VK_SAMPLE_COUNT_1_BIT,
            sharingMode   : VK_SHARING_MODE_EXCLUSIVE,
        };

        VkImage image;
        auto createErrors = vkCreateImage(logicalDevice, &createInfo, null, &image);
        enforce(!createErrors);

        VkMemoryRequirements memoryRequirements;
        vkGetImageMemoryRequirements(this.logicalDevice, image, &memoryRequirements);

        VkMemoryAllocateInfo allocInfo = {
            allocationSize  : memoryRequirements.size,
            memoryTypeIndex : findMemoryType(memoryRequirements.memoryTypeBits,
                                             VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
        };

        VkDeviceMemory memory;
        auto allocErrors =
            vkAllocateMemory(this.logicalDevice, &allocInfo, null, &memory);
        enforce(!allocErrors);

        vkBindImageMemory(logicalDevice, image, memory, 0);

        DepthResources ret = {
            image     : image,
            memory    : memory,
            imageView : createImageView(this.logicalDevice, image, imageFormat,
                                        VK_IMAGE_ASPECT_DEPTH_BIT),
        };

        return ret;
    }


    VkDescriptorSet[] createDescriptorSets (uint                  count,
                                            VkDescriptorPool      descriptorPool,
                                            VkDescriptorSetLayout descriptorSetLayout,
                                            VkBuffer[]            uniformBuffers)
        in  (uniformBuffers.length == count)
        out (r; r.length == count)
    {
        VkDescriptorSetLayout[] layouts;
        layouts.length = count;
        layouts[]      = descriptorSetLayout;

        //debug log(layouts);

        VkDescriptorSetAllocateInfo allocInfo = {
            descriptorPool     : descriptorPool,
            descriptorSetCount : count,
            pSetLayouts        : layouts.ptr,
        };

        VkDescriptorSet[] ret;
        ret.length = count;

        auto errors = vkAllocateDescriptorSets(
            this.logicalDevice, &allocInfo, ret.ptr);
        enforce(!errors, "Failed to allocate descriptor sets.");

        foreach (i, set; ret) {
            import shader_abi : Uniforms;

            VkDescriptorBufferInfo bufferInfo = {
                buffer : uniformBuffers[i],
                offset : 0,
                range  : Uniforms.sizeof,
            };

            VkWriteDescriptorSet write = {
                dstSet          : ret[i],
                dstBinding      : 0,
                dstArrayElement : 0,
                descriptorType  : VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                descriptorCount : 1,
                pBufferInfo     : &bufferInfo,
            };

            vkUpdateDescriptorSets(logicalDevice, 1, &write, 0, null);
        }

        return ret;
    }


    VulkanBuffer[] createUniformBuffers(ulong count, size_t sizeInBytes)
        out (r; r.length == count)
    {
        VulkanBuffer[] ret;
        ret.length = count;

        foreach (i; 0 .. ret.length) {
            ret[i] = createUniformBuffer(sizeInBytes);
        }

        return ret;
    }


    /// Clean up all Vulkan state, ready to shut down the application. Or recreate
    /// the entire Vulkan context. Or whatever.
    ~this() {
        // Device-level
        cleanupSwapchainWithDependents ();

        vkDestroyCommandPool           (this.logicalDevice, this.commandPool, null);
        vkDestroyPipelineLayout        (this.logicalDevice, this.pipelineLayout, null);
        vkDestroyDescriptorSetLayout   (this.logicalDevice, this.descriptorSetLayout, null);
        vkDestroyDevice                (this.logicalDevice, null);
        // Instance-level
        vkDestroyDebugUtilsMessengerEXT(this.instance, this.debugMessenger, null);
        vkDestroySurfaceKHR            (this.instance, this.surface, null);
        vkDestroyInstance              (this.instance, null);
    }


} // end Renderer


// Utility functions ...


static auto getVertexBindingDescription() {
    import shader_abi : Vertex;
    VkVertexInputBindingDescription ret = {
        binding   : 0,
        stride    : Vertex.sizeof,
        inputRate : VK_VERTEX_INPUT_RATE_VERTEX,
    };
    return ret;
}


static auto getVertexAttributeDescription() {
    import shader_abi : Vertex;
    VkVertexInputAttributeDescription[3] ret = [
        {
            binding  : 0,
            location : 0,
            format   : VK_FORMAT_R32G32B32_SFLOAT,
            offset   : Vertex.position.offsetof,
        },
        {
            binding  : 0,
            location : 1,
            format   : VK_FORMAT_R32G32B32_SFLOAT,
            offset   : Vertex.normal.offsetof,
        }
    ];
    return ret;
}


