module renderer;

import std.conv : to;
import std.exception : enforce;
import std.typecons : Nullable;
import std.experimental.logger : log;

import glfw3.api;
import erupted;
import erupted.vulkan_lib_loader;

static import globals;
import game;
import math;
import util;
import ecs;


struct BinarySemaphore
{
    void Signal  ()
        in (  !m_expectedToBeSignalled)
        out(;  m_expectedToBeSignalled)
    {
        log("Semaphore ", m_semaphore, " was signalled");
        m_expectedToBeSignalled = true;
    }

    void Wait()
        in (m_expectedToBeSignalled)
    {
        log("Semaphore ", m_semaphore, " is being waited on.");
    }

    void Unsignal()
        in (   m_expectedToBeSignalled)
        out(; !m_expectedToBeSignalled)
    {
        log("Semaphore ", m_semaphore, " was unsignalled");
        m_expectedToBeSignalled = false;
    }

    alias m_semaphore this;

    VkSemaphore m_semaphore;
    bool        m_expectedToBeSignalled;
}

// Buffer types
alias VertexBuffer  = Buffer!Vertex;
alias UniformBuffer = Buffer!Uniforms;

/// XXX: This must be a class so that it has reference semantics. Otherwise the
/// destructor will be called when it is returned from a function, freeing its
/// resources.
class Buffer(DataT)
{
    VkDevice       device   = VK_NULL_HANDLE;
    VkBuffer       buffer   = VK_NULL_HANDLE;
    VkDeviceMemory memory   = VK_NULL_HANDLE;
    ulong          size     = 0; /// Size in bytes of the buffer's storage

    invariant(device != VK_NULL_HANDLE);
    invariant(buffer != VK_NULL_HANDLE);
    invariant(memory != VK_NULL_HANDLE);
    invariant(size >= 0);

    /// How many elements of type DataT can this buffer hold?
    uint ElementCount() const
    {
        return (this.size / DataT.sizeof).to!uint;
    }

    /// Set the data in this buffer to the given value
    void MapMemoryAndSetData(DataT[] data)
    {
        import core.stdc.string : memcpy;

        void *dst = null;
        check!vkMapMemory(device, memory, 0, size, 0, &dst);
        memcpy(dst, data.ptr, (data.length * DataT.sizeof));
        vkUnmapMemory(device, memory);
    }

    ~this()
    {
        log("Destructor: ", this);
        vkDestroyBuffer(device, buffer, null);
        vkFreeMemory   (device, memory, null);
    }
}

// Extension function pointers -- these need to be loaded before called
PFN_vkCreateDebugUtilsMessengerEXT  vkCreateDebugUtilsMessengerEXT;
PFN_vkDestroyDebugUtilsMessengerEXT vkDestroyDebugUtilsMessengerEXT;

class Uniforms
{
    // Ensure this is equal to the one defined in shader.vert
    enum MAX_MODEL_UNIFORMS = 1000;

    mat4[MAX_MODEL_UNIFORMS] models;
    mat4                     view;
    mat4                     projection;
}

struct Vertex
{
    // Ensure updates here are reflected in Vertex.getAttributeDescription
    vec3 position; /// Model-space position of this vertex
    vec3 normal;   /// Vertex normal vector

    static auto GetBindingDescription()
    {
        VkVertexInputBindingDescription ret = {
            binding   : 0,
            stride    : Vertex.sizeof,
            inputRate : VK_VERTEX_INPUT_RATE_VERTEX,
        };
        return ret;
    }

    static auto GetAttributeDescription()
    {
        VkVertexInputAttributeDescription[2] ret = [
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
}

class Renderer
{
    enum kDepthFormat = VK_FORMAT_D16_UNORM;

public:

    /*
    ---------------------------------------------------------------------------
    --  State
    ---------------------------------------------------------------------------
    */

    VkInstance       instance;
    VkSurfaceKHR     surface;
    VkPhysicalDevice physicalDevice;
    VkDevice         logicalDevice;
    VkQueue          graphicsQueue;
    VkQueue          presentQueue;

    VkDebugUtilsMessengerEXT debugMessenger;

    VkDescriptorSetLayout descriptorSetLayout;
    VkPipelineLayout      pipelineLayout;
    VkCommandPool         commandPool;
    Swapchain             swapchain;

    enum RendererState { BetweenFrames, AcceptingCommands, ReadyToPresent }
    RendererState m_state = RendererState.BetweenFrames;

    /*
    ---------------------------------------------------------------------------
    --  Functions
    ---------------------------------------------------------------------------
    */

    /// Render (present) the given frame.
    void render(Frame frame)
        in (  m_state == RendererState.ReadyToPresent)
        out(; m_state == RendererState.BetweenFrames)
    {
        VkPipelineStageFlags waitStages = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;

        VkSubmitInfo submitInfo = {
            waitSemaphoreCount   : 1,
            pWaitSemaphores      : &this.swapchain.imageAvailableSemaphore.m_semaphore,
            // Wait until image is available. This resets the semaphore when
            // done waiting.
            pWaitDstStageMask    : &waitStages,
            signalSemaphoreCount : 1,
            pSignalSemaphores    : &this.swapchain.renderFinishedSemaphore.m_semaphore, // Signal that rendering is done
            commandBufferCount   : 1,
            pCommandBuffers      : &this.swapchain.commandBuffers[frame.imageIndex],
        };

        this.swapchain.imageAvailableSemaphore.Wait;

        // Signals commandBufferReadyFence when done, so we can re-use the
        // command buffer.
        check!vkQueueSubmit(this.graphicsQueue, 1, &submitInfo, this.swapchain.commandBufferReadyFence);

        this.swapchain.imageAvailableSemaphore.Unsignal;
        this.swapchain.renderFinishedSemaphore.Signal;

        VkPresentInfoKHR presentInfo = {
            waitSemaphoreCount : 1,
            pWaitSemaphores    : &this.swapchain.renderFinishedSemaphore.m_semaphore,
            // Wait for rendering to be done before presenting the image. This
            // resets renderFinishedSemaphore.
            swapchainCount     : 1,
            pSwapchains        : &this.swapchain.swapchain,
            pImageIndices      : &frame.imageIndex,
            pResults           : null,
        };

        this.swapchain.renderFinishedSemaphore.Wait;

        // Present the queue, and handle window resizes if needed
        auto queuePresentResult = check!vkQueuePresentKHR(presentQueue, &presentInfo);

        this.swapchain.renderFinishedSemaphore.Unsignal;
        m_state = RendererState.BetweenFrames;

        debug switch (queuePresentResult)
        {
            case VK_ERROR_OUT_OF_DATE_KHR: log("Out of date!"); break;
            case VK_SUBOPTIMAL_KHR:        log("Suboptimal!");  break;
            default: break;
        }

        if (queuePresentResult == VK_ERROR_OUT_OF_DATE_KHR ||
            queuePresentResult == VK_SUBOPTIMAL_KHR ||
            globals.windowWasResized)
        {
            debug log("Recreating swapchain.");
            globals.windowWasResized = false;
            this.swapchain = recreateSwapchain();
        }
    }


    /// Will our Vulkan instance support all the provided layers?
    bool haveAllRequiredLayers(const(char)*[] requiredLayers)
    {
        uint layerCount;
        vkEnumerateInstanceLayerProperties(&layerCount, null);
        enforce(layerCount > 0, "No layers available? This is weird.");

        VkLayerProperties[] availableLayers;
        availableLayers.length = layerCount;
        vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.ptr);

        uint numRequiredLayersFound = 0;

        foreach (requiredLayer; requiredLayers)
        {
            foreach (layer; availableLayers)
            {
                immutable string layerName = layer.layerName.idup;
                import core.stdc.string : strcmp;

                if (strcmp(requiredLayer, layerName.ptr) == 0)
                {
                    ++numRequiredLayersFound;
                    break;
                }
            }
        }

        return numRequiredLayersFound == requiredLayers.length;
    }

    /// Initialise the renderer state, ready to render buffers!
    void initialise(
        VkApplicationInfo appInfo,
        const(char)*[] requiredLayers,
        const(char)*[] requiredInstanceExtensions,
        const(char)*[] requiredDeviceExtensions
    )
    {
        // Load initial set of Vulkan functions

        {
            auto vulkanLoadedOkay = loadGlobalLevelFunctions;
            enforce(vulkanLoadedOkay, "Failed to load Vulkan functions!");
        }

        enforce(haveAllRequiredLayers(requiredLayers));
        debug log("We have all required extensions!");

        // Glfw Extensions

        {
            uint count;
            auto glfwExtensions = glfwGetRequiredInstanceExtensions(&count);

            foreach (i; 0 .. count)
            {
                requiredInstanceExtensions ~= glfwExtensions[i];
            }
        }

        // Create the instance

        {
            VkInstanceCreateInfo createInfo = {
                pApplicationInfo        : &appInfo,
                enabledExtensionCount   : requiredInstanceExtensions.GetLengthAsUint(),
                ppEnabledExtensionNames : requiredInstanceExtensions.ptr,
                enabledLayerCount       : requiredLayers.GetLengthAsUint(),
                ppEnabledLayerNames     : requiredLayers.ptr,
            };

            check!vkCreateInstance(&createInfo, null, &instance);
        }

        loadInstanceLevelFunctions(instance);
        debug log("Instance created, and instance-level functions loaded!");

        // Set up debug messenger

        this.debugMessenger = createDebugMessenger();

        // Create rendering surface

        {
            // Can't really use check! here because we need to cast the result.
            import glfw3.vulkan : glfwCreateWindowSurface;
            auto errors = cast(erupted.VkResult)glfwCreateWindowSurface(
                instance, globals.window, null, cast(ulong*)&this.surface);
            assert(!errors);
        }

        // Select physical device

        this.physicalDevice = selectPhysicalDevice(this.instance, requiredDeviceExtensions);

        // Create the logical device
        QueueFamilies queueFamilies = QueueFamilies.Get(this.physicalDevice, this.surface);

        {
            static float[1] queuePriorities = [1.0];

            VkDeviceQueueCreateInfo presentQueueCreateInfo = {
                queueFamilyIndex : queueFamilies.present,
                queueCount       : 1,
                pQueuePriorities : queuePriorities.ptr,
            };

            VkDeviceQueueCreateInfo graphicsQueueCreateInfo = {
                queueFamilyIndex : queueFamilies.graphics,
                queueCount       : 1,
                pQueuePriorities : queuePriorities.ptr,
            };

            VkDeviceQueueCreateInfo[] queueCreateInfos;

            queueCreateInfos ~= graphicsQueueCreateInfo;

            // Append presentFamily only if it's different to graphics family.
            if (queueFamilies.present != queueFamilies.graphics)
            {
                queueCreateInfos ~= presentQueueCreateInfo;
            }

            VkPhysicalDeviceFeatures deviceFeatures;

            VkDeviceCreateInfo createInfo = {
                pQueueCreateInfos       : queueCreateInfos.ptr,
                queueCreateInfoCount    : queueCreateInfos.GetLengthAsUint(),
                pEnabledFeatures        : &deviceFeatures,
                enabledExtensionCount   : requiredDeviceExtensions.GetLengthAsUint(),
                ppEnabledExtensionNames : requiredDeviceExtensions.ptr,
            };

            check!vkCreateDevice(physicalDevice, &createInfo, null, &logicalDevice);
        }

        // Load Vulkan functions for the VkDevice (via erupted)
        loadDeviceLevelFunctions(logicalDevice);
        debug log("Logical device created, and device-level functions loaded!");

        // Set queues for this device
        vkGetDeviceQueue(logicalDevice, queueFamilies.graphics, 0, &graphicsQueue);
        vkGetDeviceQueue(logicalDevice, queueFamilies.present, 0, &presentQueue);

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

            check!vkCreateDescriptorSetLayout(logicalDevice, &layoutInfo, null, &descriptorSetLayout);
        }

        // Create pipeline layout

        {
            VkPipelineLayoutCreateInfo createInfo = {
                setLayoutCount : 1,
                pSetLayouts    : &descriptorSetLayout,
            };

            check!vkCreatePipelineLayout(logicalDevice, &createInfo, null, &pipelineLayout);
        }

        // Create command pool

        {
            VkCommandPoolCreateInfo createInfo = {
                queueFamilyIndex : queueFamilies.graphics,
                flags            : VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            };

            check!vkCreateCommandPool(logicalDevice, &createInfo, null, &commandPool);
        }

        // Create swapchain

        this.swapchain = createSwapchain();

    } // end init()

    VkDebugUtilsMessengerEXT createDebugMessenger()
    {
        extern (Windows) VkBool32
        debugCallback(
            VkDebugUtilsMessageSeverityFlagBitsEXT      messageSeverity,
            VkDebugUtilsMessageTypeFlagsEXT             messageType,
            const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData,
            void*                                       pUserData
        )
            nothrow @nogc
        {
            import core.stdc.stdio : snprintf, puts, fflush, stdout;
            import std.string : format;
            enum MsgLen = 1000;
            scope char[MsgLen] msg;
            snprintf(
                msg.ptr,
                MsgLen,
                "VULKAN SPEC VIOLATION: %s\n  -> %s\n",
                pCallbackData.pMessageIdName, pCallbackData.pMessage
            );
            puts(msg.ptr);
            return VK_FALSE;
        }

        VkDebugUtilsMessengerCreateInfoEXT createInfo = {
            messageSeverity : //VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
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
        check!vkCreateDebugUtilsMessengerEXT(this.instance, &createInfo, null, &ret);

        return ret;
    }


    VkSwapchainKHR
    CreateVkSwapchain(GLFWwindow* window, VkPhysicalDevice physicalDevice, VkSurfaceKHR surface)
    {
        const support = SwapchainSupportDetails.Get(physicalDevice, surface);
        immutable surfaceFormat = SelectSurfaceFormat(support.formats);

        VkSwapchainCreateInfoKHR swapchainCreateInfo = {
            surface               : surface,
            minImageCount         : support.capabilities.minImageCount,
            imageFormat           : surfaceFormat.format,
            imageColorSpace       : surfaceFormat.colorSpace,
            imageExtent           : SelectExtent(window, support.capabilities),
            imageArrayLayers      : 1,
            imageUsage            : VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            imageSharingMode      : VK_SHARING_MODE_EXCLUSIVE,
            queueFamilyIndexCount : 0,
            pQueueFamilyIndices   : null,
            preTransform          : support.capabilities.currentTransform,
            compositeAlpha        : VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            presentMode           : SelectPresentMode(support.presentModes),
            clipped               : VK_TRUE,
            oldSwapchain          : VK_NULL_HANDLE,
        };

        VkSwapchainKHR ret;
        check!vkCreateSwapchainKHR(logicalDevice, &swapchainCreateInfo, null, &ret);

        return ret;
    }


    VkImageView createImageView(VkDevice           logicalDevice,
                                VkImage            image,
                                VkFormat           format,
                                VkImageAspectFlags aspectMask)
    {
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
        check!vkCreateImageView(logicalDevice, &createInfo, null, &ret);

        return ret;
    }


    VkImageView[] createImageViewsForSwapchain(VkSwapchainKHR swapchain)
    {
        // Images

        uint numImages;
        VkImage[] images;

        vkGetSwapchainImagesKHR(logicalDevice, swapchain, &numImages, null);
        images.length = numImages;
        vkGetSwapchainImagesKHR(logicalDevice, swapchain, &numImages, images.ptr);

        auto support = SwapchainSupportDetails.Get(this.physicalDevice, this.surface);
        auto format  = SelectSurfaceFormat(support.formats).format;

        // Image views

        VkImageView[] ret;
        ret.length = images.length;

        foreach(i, image; images)
        {
            ret[i] = createImageView(logicalDevice, image, format, VK_IMAGE_ASPECT_COLOR_BIT);
        }

        return ret;
    }


    struct Swapchain
    {
        uint GetNumImages() inout
        {
            return imageViews.GetLengthAsUint();
        }

        void SetUniformDataForFrame(uint imageIndex, Uniforms data)
        {
            SendNewData(commandBuffers[imageIndex], uniformBuffers[imageIndex], [data]);
        }

        VkSwapchainKHR    swapchain;
        VkRenderPass      renderPass;
        VkDescriptorPool  descriptorPool;
        DepthResources    depthResources;
        VkPipeline        pipeline;

        // Per-image (per-frame) data
        VkImageView             []imageViews;
        VkFramebuffer           []framebuffers;
        VkDescriptorSet         []descriptorSets;
        UniformBuffer           []uniformBuffers;
        VkCommandBuffer         []commandBuffers;

        invariant(imageViews.length == framebuffers.length);
        invariant(imageViews.length == descriptorSets.length);
        invariant(imageViews.length == uniformBuffers.length);
        invariant(imageViews.length == commandBuffers.length);

        /// Signalled when the commandBuffer for this image can be submitted
        BinarySemaphore         imageAvailableSemaphore;
        /// Signalled when this frame has been submitted to be presented
        BinarySemaphore         renderFinishedSemaphore;
        /// Signalled when the command buffer can be re-used
        VkFence                 commandBufferReadyFence;
    }


    Swapchain createSwapchain()
    {
        Swapchain ret;

        vkDeviceWaitIdle(this.logicalDevice);

        ret.swapchain      = this.CreateVkSwapchain(globals.window, this.physicalDevice, this.surface);
        ret.imageViews     = this.createImageViewsForSwapchain(ret.swapchain);

        immutable numImages = ret.imageViews.GetLengthAsUint();

        debug log("Creating swapchain for ", numImages, " images");

        ret.renderPass     = CreateRenderPass(
            this.logicalDevice,
            SelectSurfaceFormat(SwapchainSupportDetails.Get(this.physicalDevice, this.surface).formats).format,
            kDepthFormat
        );

        ret.pipeline       = this.createGraphicsPipeline(ret.renderPass);
        ret.depthResources = this.createDepthResources();
        ret.framebuffers   = this.createFramebuffers(ret.imageViews, ret.depthResources.imageView, ret.renderPass);

        ret.uniformBuffers = this.createUniformBuffers(numImages);
        ret.descriptorPool = this.createDescriptorPool(numImages, VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER);
        ret.descriptorSets = this.createDescriptorSets(numImages, ret.descriptorPool, this.descriptorSetLayout, ret.uniformBuffers);
        ret.commandBuffers = this.createCommandBuffers(numImages);
        ret.imageAvailableSemaphore = this.createSemaphore();
        ret.renderFinishedSemaphore = this.createSemaphore();
        ret.commandBufferReadyFence = this.createFence(VK_FENCE_CREATE_SIGNALED_BIT);

        return ret;
    }


    /// Clean up a swapchain and all its dependent items. There are a lot of them.
    /// The commandPool and pipelineLayout are NOT destroyed.
    void cleanupSwapchain(Swapchain sc)
    {
        vkDeviceWaitIdle(logicalDevice);

        foreach (framebuffer; sc.framebuffers)
        {
            vkDestroyFramebuffer(this.logicalDevice, framebuffer, null);
        }

        vkFreeCommandBuffers(this.logicalDevice, this.commandPool, this.swapchain.GetNumImages(), sc.commandBuffers.ptr);

        vkDestroySemaphore (this.logicalDevice, sc.imageAvailableSemaphore.m_semaphore, null);
        vkDestroySemaphore (this.logicalDevice, sc.renderFinishedSemaphore.m_semaphore, null);
        vkDestroyFence     (this.logicalDevice, sc.commandBufferReadyFence, null);
        vkDestroyPipeline  (this.logicalDevice, sc.pipeline, null);
        vkDestroyRenderPass(this.logicalDevice, sc.renderPass, null);

        foreach (view; sc.imageViews)
        {
            vkDestroyImageView(this.logicalDevice, view, null);
        }

        vkDestroyImageView(this.logicalDevice, sc.depthResources.imageView, null);
        vkDestroyImage    (this.logicalDevice, sc.depthResources.image, null);
        vkFreeMemory      (this.logicalDevice, sc.depthResources.memory, null);

        foreach (buf; sc.uniformBuffers)
        {
            vkDestroyBuffer(this.logicalDevice, buf.buffer, null);
            vkFreeMemory   (this.logicalDevice, buf.memory, null);
        }

        vkFreeDescriptorSets(
            this.logicalDevice,
            sc.descriptorPool,
            sc.descriptorSets.GetLengthAsUint,
            sc.descriptorSets.ptr
        );

        vkDestroyDescriptorPool(this.logicalDevice, sc.descriptorPool, null);
        vkDestroySwapchainKHR  (this.logicalDevice, sc.swapchain, null);
    }


    Swapchain recreateSwapchain()
    {
        vkDeviceWaitIdle(this.logicalDevice);
        cleanupSwapchain(this.swapchain);
        return createSwapchain();
    }


    VkFence createFence(VkFenceCreateFlags flags = 0)
    {
        VkFence ret;
        VkFenceCreateInfo info = { flags : flags, };
        check!vkCreateFence(this.logicalDevice, &info, null, &ret);
        return ret;
    }


    BinarySemaphore createSemaphore()
    {
        VkSemaphore ret;
        VkSemaphoreCreateInfo info;
        check!vkCreateSemaphore(this.logicalDevice, &info, null, &ret);
        return BinarySemaphore(ret, false);
    }


    /// Create the given number of command buffers using the Renderer's current
    /// command pool.
    VkCommandBuffer[] createCommandBuffers(uint count) {
        auto ret = new VkCommandBuffer[count];

        VkCommandBufferAllocateInfo allocateInfo = {
            commandPool        : commandPool,
            level              : VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            commandBufferCount : count,
        };

        check!vkAllocateCommandBuffers(this.logicalDevice, &allocateInfo, ret.ptr);

        debug log("Allocated command buffers: ", ret);
        return ret;
    }

    /// Create a framebuffer for each provided vkImageView.
    VkFramebuffer[] createFramebuffers(VkImageView[] imageViews,
                                       VkImageView   depthImageView,
                                       VkRenderPass  renderPass)
    {
        VkFramebuffer[] ret;
        ret.length = imageViews.length;

        auto extent = getSurfaceExtent();

        foreach (i, view; imageViews) {
            VkImageView[2] attachments = [ view, depthImageView ];

            VkFramebufferCreateInfo createInfo = {
                renderPass      : renderPass,
                attachmentCount : attachments.GetLengthAsUint(),
                pAttachments    : attachments.ptr,
                width           : extent.width,
                height          : extent.height,
                layers          : 1,
            };

           check!vkCreateFramebuffer(this.logicalDevice, &createInfo, null, &ret[i]);
        }

        return ret;
    }

    VkExtent2D getSurfaceExtent()
    {
        const support = SwapchainSupportDetails.Get(this.physicalDevice, this.surface);
        return SelectExtent(globals.window, support.capabilities);
    }

    /// Set up the graphics pipeline for our application. There are a lot of
    /// hardcoded properties about our pipeline in this function -- it's not
    /// nearly as agnostic as it may appear.
    VkPipeline createGraphicsPipeline(VkRenderPass renderPass)
    {
        VkShaderModule vertModule = CreateShaderModule(logicalDevice, "./source/vert.spv");
        VkShaderModule fragModule = CreateShaderModule(logicalDevice, "./source/frag.spv");

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

        auto bindingDescription    = Vertex.GetBindingDescription;
        auto attributeDescriptions = Vertex.GetAttributeDescription;

        VkPipelineVertexInputStateCreateInfo vertexInputCreateInfo = {
            vertexBindingDescriptionCount   : 1,
            pVertexBindingDescriptions      : &bindingDescription,
            vertexAttributeDescriptionCount : attributeDescriptions.GetLengthAsUint(),
            pVertexAttributeDescriptions    : attributeDescriptions.ptr,
        };

        VkPipelineInputAssemblyStateCreateInfo inputAssemblyCreateInfo = {
            topology               : VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
            primitiveRestartEnable : VK_FALSE,
        };

        auto extent = getSurfaceExtent();

        /// NOTE that our viewport is flipped upside-down so we can use Y-up,
        /// where Vulkan normally uses Y-down.
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
            stageCount          : shaderStages.GetLengthAsUint(),
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

        check!vkCreateGraphicsPipelines(logicalDevice, VK_NULL_HANDLE, 1, &createInfo, null, &ret);

        vkDestroyShaderModule(logicalDevice, fragModule, null);
        vkDestroyShaderModule(logicalDevice, vertModule, null);

        return ret;
    }

    struct QueueFamilies
    {
        enum kInvalid = uint.max;

        uint graphics = kInvalid;
        uint present  = kInvalid;

        bool IsValid() inout
        {
            return graphics != kInvalid
                && present  != kInvalid;
        }

        /// Select queue families that meet the criteria defined in this function.
        static QueueFamilies Get(VkPhysicalDevice physicalDevice, VkSurfaceKHR surface)
        {
            VkQueueFamilyProperties[] queueFamilies;
            uint queueFamilyCount;
            vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, null);
            queueFamilies.length = queueFamilyCount;
            vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, queueFamilies.ptr);

            QueueFamilies ret;

            foreach (i, family; queueFamilies)
            {
                immutable index = i.to!uint;

                bool supportsGraphics = family.queueFlags & VK_QUEUE_GRAPHICS_BIT;

                if (supportsGraphics)
                {
                    ret.graphics = index;
                }

                VkBool32 supportsPresent = false;
                vkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice, index, surface, &supportsPresent);

                // NOTE: We may want to use different queue families for graphics
                // and present. Not sure why, but the tutorial said we would.
                if (supportsPresent)
                {
                    ret.present = index;
                }
            }

            assert(ret.IsValid(), "Failed to find suitable queue families.");
            return ret;
        }
    }

    /// Is this device suitable for our purposes?
    bool isSuitable(VkPhysicalDevice particularPhysicalDevice,
                    const(char)*[]   requiredDeviceExtensions)
    {
        // Confirm device is a discrete GPU
        VkPhysicalDeviceProperties deviceProperties;
        vkGetPhysicalDeviceProperties(particularPhysicalDevice, &deviceProperties);

        // Confirm device supports our desired queue families
        const families = QueueFamilies.Get(particularPhysicalDevice, this.surface);
        if (!families.IsValid())
        {
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
        // string. But the key to the extensionFound hashmap needs to be a
        // string, so it will hash the contents and not just the address, cause
        // the addresses could be anything.

        import std.string    : fromStringz;
        import std.algorithm : map;

        bool[string] extensionFound;

        foreach (name; requiredDeviceExtensions.map!(s => s.fromStringz))
        {
            extensionFound[name] = false;
        }

        foreach (name; availableDeviceExtensions.map!(ext => ext.extensionName.ptr.fromStringz.idup))
        {
            if (name in extensionFound)
            {
                extensionFound[name] = true;
            }
        }

        foreach (name; requiredDeviceExtensions.map!(s => s.fromStringz))
        {
            if (!extensionFound[name])
            {
                // Not all extensions are supported -- device isn't suitable
                return false;
            }
        }

        // Confirm swapchain support
        const support = SwapchainSupportDetails.Get(particularPhysicalDevice, this.surface);

        return support.formats.length != 0 && support.presentModes.length != 0;
    }

    /// Select a physical device available in the instance based on whether it
    /// satisfies isSuitable().
    VkPhysicalDevice selectPhysicalDevice(VkInstance instance, const(char)*[] requiredDeviceExtensions)
    {
        uint numPhysicalDevices;
        vkEnumeratePhysicalDevices(this.instance, &numPhysicalDevices, null);
        enforce(numPhysicalDevices > 0, "Couldn't find any devices!!");

        VkPhysicalDevice[] physicalDevices;
        physicalDevices.length = numPhysicalDevices;
        vkEnumeratePhysicalDevices(this.instance, &numPhysicalDevices,
                                   physicalDevices.ptr);

        debug log("Physical devices: ", physicalDevices);

        import std.algorithm : filter;
        auto suitableDevices = physicalDevices.filter!(
            d => isSuitable(d, requiredDeviceExtensions)
        );

        debug log("Suitable devices: ", suitableDevices);

        if (suitableDevices.empty)
        {
            throw new Error("Couldn't find a suitable physical device!");
        }

        return suitableDevices.front;
    }

    /// Acquire the imageIndex for the next frame, and signal the
    /// imageAvailableSemaphore which the queue submit will wait for.
    uint NextFrame()
        in (m_state == RendererState.BetweenFrames)
    {
        uint imageIndex;

        check!vkAcquireNextImageKHR(
            this.logicalDevice,
            this.swapchain.swapchain,
            ulong.max, // timeout (ns)
            this.swapchain.imageAvailableSemaphore,
            // Signalled when the image is grabbed. Note that if this function
            // doesn't return VK_SUCCESS, this may not be signalled.
            VK_NULL_HANDLE,
            &imageIndex
        );

        this.swapchain.imageAvailableSemaphore.Signal;
        return imageIndex;
    }

    /*
    ---------------------------------------------------------------------------
    --  Buffers
    ---------------------------------------------------------------------------
    */


    Buffer!DataT CreateBuffer(DataT)(
        VkBufferUsageFlags    usage,
        VkMemoryPropertyFlags memoryPropertyFlags,
        size_t                numElements = 1
    )
        in  (this.logicalDevice != VK_NULL_HANDLE)
        in  (numElements > 0)
        out (b; b.size     == numElements * DataT.sizeof)
        out (b; b.device   == this.logicalDevice)
        out (b; b.buffer   != VK_NULL_HANDLE)
        out (b; b.memory   != VK_NULL_HANDLE)
    {
        auto ret = new Buffer!DataT;

        ret.size     = numElements * DataT.sizeof;
        ret.device   = this.logicalDevice;

        // Create buffer
        VkBufferCreateInfo bufInfo = {
            size        : ret.size,
            usage       : usage,
            sharingMode : VK_SHARING_MODE_EXCLUSIVE,
            // ^^ I guess this is where you'd do buffer aliasing etc
        };

        check!vkCreateBuffer(ret.device, &bufInfo, null, &ret.buffer);
        log("Created buffer ", ret.buffer);

        // Create ret.memory
        VkMemoryRequirements memRequirements;
        vkGetBufferMemoryRequirements(ret.device, ret.buffer, &memRequirements);

        VkMemoryAllocateInfo memInfo = {
            allocationSize  : memRequirements.size,
            memoryTypeIndex : this.findMemoryType(
                memRequirements.memoryTypeBits, memoryPropertyFlags),
        };

        check!vkAllocateMemory(ret.device, &memInfo, null, &ret.memory);
        log("Created Memory ", ret.memory);

        check!vkBindBufferMemory(ret.device, ret.buffer, ret.memory, 0);

        log(__FUNCTION__, " Returning: ", &ret);
        return ret;
    }


    /// Issue a command to render the given number of instances of the given
    /// vertex buffer.
    void issueRenderCommands(DataT)(uint         imageIndex,
                                    Buffer!DataT buffer,
                                    uint         numInstances)
        in (m_state == RendererState.AcceptingCommands)
    {
        VkBuffer[1]     buffers = [buffer.buffer];
        VkDeviceSize[1] offsets = [0];

        auto cb = this.swapchain.commandBuffers[imageIndex];

        debug log("Rendering VkBuffer ", buffer.buffer, " ", numInstances, " times");

        vkCmdBindVertexBuffers(cb, 0, 1, buffers.ptr, offsets.ptr);
        vkCmdDraw             (cb, buffer.ElementCount(), numInstances, 0, 0);
    }

    /// Reset the command buffer for this frame, then move it to the Recording
    /// state.
    void beginCommandsForFrame(uint imageIndex, Uniforms uniformData)
        in  (  m_state == RendererState.BetweenFrames)
        out (; m_state == RendererState.AcceptingCommands)
    {
        auto cb = this.swapchain.commandBuffers[imageIndex];

        log("Waiting for commandBufferReadyFence");

        // Wait for the command buffer to be ready (signalled by vkQueueSubmit)
        check!vkWaitForFences(this.logicalDevice, 1, &this.swapchain.commandBufferReadyFence, false, ulong.max);

        log("Finished waiting for commandBufferReadyFence");

        // Reset the fence for next time
        check!vkResetFences  (this.logicalDevice, 1, &this.swapchain.commandBufferReadyFence);

        log("Reset commandBufferReadyFence");

        // Reset the command buffer, putting it in the Initial state
        check!vkResetCommandBuffer(cb, cast(VkCommandBufferResetFlags) 0);

        // Begin the command buffer, putting it in the Recording state
        VkCommandBufferBeginInfo beginInfo = {
            flags : VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };

        check!vkBeginCommandBuffer(cb, &beginInfo);
        m_state = RendererState.AcceptingCommands;

        // Send updated uniform data
        swapchain.SetUniformDataForFrame(imageIndex, uniformData);

        // Start a render pass
        VkRenderPassBeginInfo info = {
            renderPass  : this.swapchain.renderPass,
            framebuffer : this.swapchain.framebuffers[imageIndex],
            renderArea  : {
                offset : {0, 0},
                extent : this.getSurfaceExtent(),
            },
            clearValueCount : globals.clearValues.GetLengthAsUint(),
            pClearValues    : globals.clearValues.ptr,
        };

        vkCmdBeginRenderPass   (cb, &info, VK_SUBPASS_CONTENTS_INLINE);
        vkCmdBindPipeline      (cb, VK_PIPELINE_BIND_POINT_GRAPHICS,
                                this.swapchain.pipeline);
        vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_GRAPHICS,
                                this.pipelineLayout, 0, 1,
                                &this.swapchain.descriptorSets[imageIndex], 0,
                                null);

    }

    /// Indicate that we are finished recording rendering commands for this
    /// frame, and the command buffer may be submitted.
    void endCommandsForFrame(uint imageIndex)
        in  (  m_state == RendererState.AcceptingCommands)
        out (; m_state == RendererState.ReadyToPresent)
    {
        auto cb = this.swapchain.commandBuffers[imageIndex];
        vkCmdEndRenderPass(cb);
        check!vkEndCommandBuffer(cb);
        m_state = RendererState.ReadyToPresent;
    }

    /**
        Select a memory type that satisfies the requested properties.

        AFAICT this should be able to be immutable but the physicalDevice
        parameter to vkGetPhysicalDeviceMemoryProperties is not const, so uh,
        it has to be non-const.
    */
    uint findMemoryType(uint typeFilter, VkMemoryPropertyFlags requestedProperties)
    {
        VkPhysicalDeviceMemoryProperties memProperties;
        vkGetPhysicalDeviceMemoryProperties(
            this.physicalDevice, &memProperties);

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

    VkDescriptorPool createDescriptorPool(uint numDescriptors, VkDescriptorType type)
    {
        VkDescriptorPoolSize poolSize = {
            type            : type,
            descriptorCount : numDescriptors,
        };

        VkDescriptorPoolCreateInfo createInfo = {
            poolSizeCount : 1,
            pPoolSizes    : &poolSize,
            maxSets       : numDescriptors,
            flags         : VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
        };

        VkDescriptorPool ret;

        check!vkCreateDescriptorPool(this.logicalDevice, &createInfo, null, &ret);

        return ret;
    }

    struct DepthResources
    {
        VkImage        image;
        VkImageView    imageView;
        VkDeviceMemory memory;
    }

    DepthResources createDepthResources()
    {
        VkExtent2D extent = this.getSurfaceExtent();

        VkImageCreateInfo createInfo = {
            imageType     : VK_IMAGE_TYPE_2D,
            extent        : { width: extent.width, height: extent.height, depth: 1 },
            mipLevels     : 1,
            arrayLayers   : 1,
            format        : kDepthFormat,
            tiling        : VK_IMAGE_TILING_OPTIMAL,
            initialLayout : VK_IMAGE_LAYOUT_UNDEFINED,
            usage         : VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
            samples       : VK_SAMPLE_COUNT_1_BIT,
            sharingMode   : VK_SHARING_MODE_EXCLUSIVE,
        };

        VkImage image;
        check!vkCreateImage(this.logicalDevice, &createInfo, null, &image);

        VkMemoryRequirements memoryRequirements;
        vkGetImageMemoryRequirements(this.logicalDevice, image, &memoryRequirements);

        VkMemoryAllocateInfo allocInfo = {
            allocationSize  : memoryRequirements.size,
            memoryTypeIndex : findMemoryType(memoryRequirements.memoryTypeBits,
                                             VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
        };

        VkDeviceMemory memory;
        check!vkAllocateMemory(this.logicalDevice, &allocInfo, null, &memory);
        check!vkBindImageMemory(this.logicalDevice, image, memory, 0);

        DepthResources ret = {
            image     : image,
            memory    : memory,
            imageView : createImageView(this.logicalDevice, image, kDepthFormat,
                                        VK_IMAGE_ASPECT_DEPTH_BIT),
        };

        return ret;
    }

    VkDescriptorSet[] createDescriptorSets(
        uint                  count,
        VkDescriptorPool      descriptorPool,
        VkDescriptorSetLayout descriptorSetLayout,
        UniformBuffer[]       uniformBuffers
    )
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

        check!vkAllocateDescriptorSets(this.logicalDevice, &allocInfo, ret.ptr);

        foreach (i, set; ret)
        {
            VkDescriptorBufferInfo bufferInfo = {
                buffer : uniformBuffers[i].buffer,
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

    UniformBuffer[] createUniformBuffers(ulong count)
        out (ret; ret.length == count)
        // out (ret; !ret.containsDuplicates)
    {
        auto ret = new UniformBuffer[count];
        foreach (ref buf; ret)
        {
            buf = CreateBuffer!Uniforms(
                (VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT  | VK_BUFFER_USAGE_TRANSFER_DST_BIT),
                (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)
            );
        }
        return ret;
    }

    /// Clean up all Vulkan state, ready to shut down the application. Or
    /// recreate the entire Vulkan context. Or whatever.
    ~this()
    {
        log("Destructor: ", this);
        // Device-level
        cleanupSwapchain(this.swapchain);

        vkDestroyCommandPool           (this.logicalDevice, this.commandPool, null);
        vkDestroyPipelineLayout        (this.logicalDevice, this.pipelineLayout, null);
        vkDestroyDescriptorSetLayout   (this.logicalDevice, this.descriptorSetLayout, null);
        vkDestroyDevice                (this.logicalDevice, null);
        // Instance-level
        if (this.debugMessenger)
        {
            vkDestroyDebugUtilsMessengerEXT(this.instance, this.debugMessenger, null);
        }
        vkDestroySurfaceKHR            (this.instance, this.surface, null);
        vkDestroyInstance              (this.instance, null);
    }

} // end struct Renderer


VkPresentModeKHR SelectPresentMode(in VkPresentModeKHR[] presentModes)
    pure
{
    import std.algorithm : canFind;

    if (presentModes.canFind(VK_PRESENT_MODE_MAILBOX_KHR))
    {
        // Triple-buffered. Might prefer IMMEDIATE for non-vsync.
        return VK_PRESENT_MODE_MAILBOX_KHR;
    }

    // Fallback case -- FIFO is guaranteed to be available
    return VK_PRESENT_MODE_FIFO_KHR;
}


VkSurfaceFormatKHR SelectSurfaceFormat(in VkSurfaceFormatKHR[] formats)
    pure
    in (formats.length != 0)
{
    foreach (format; formats)
    {
        if (format.format     == VK_FORMAT_B8G8R8_SRGB &&
            format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
        {
            return format;
        }
    }

    return formats[0];
}


VkShaderModule CreateShaderModule(VkDevice logicalDevice, string path)
{
    import std.stdio : File;
    auto file = File(path, "rb");
    auto data = file.rawRead(new uint[file.size / uint.sizeof]);

    VkShaderModuleCreateInfo createInfo = {
        codeSize : data.length * uint.sizeof,
        pCode    : data.ptr,
    };

    VkShaderModule ret;
    check!vkCreateShaderModule(logicalDevice, &createInfo, null, &ret);

    return ret;
}

// window can't be a const* because glfwGetFrameBufferSize for some reason
// doesn't take one?? Also means this function can't be pure...
VkExtent2D SelectExtent(   GLFWwindow*              window,
                        in VkSurfaceCapabilitiesKHR capabilities)
{
    // If width/height are set to 0xFFFFFFFF (UINT32_MAX) then the swapchain
    // gets to set the size of the extent (vkspec page 1153).

    if (capabilities.currentExtent.width != 0xFFFFFFFF)
    {
        // We're required to use the provided extent
        return capabilities.currentExtent;
    }

    // We get to choose the size of the surface, so we use the closest to the
    // size of the window as is valid.
    debug log("We're doing the surface extent translation thing.");

    int width, height;
    glfwGetFramebufferSize(window, &width, &height);

    import std.algorithm : clamp;

    immutable minWidth  = capabilities.minImageExtent.width;
    immutable maxWidth  = capabilities.maxImageExtent.width;
    immutable minHeight = capabilities.minImageExtent.height;
    immutable maxHeight = capabilities.maxImageExtent.height;

    import std.conv : to;

    VkExtent2D ret = {
        width  :  width.clamp(minWidth,  maxWidth ).to!uint,
        height : height.clamp(minHeight, maxHeight).to!uint,
    };

    return ret;
}


struct SwapchainSupportDetails
{
    VkSurfaceCapabilitiesKHR   capabilities;
    VkSurfaceFormatKHR       []formats;
    VkPresentModeKHR         []presentModes;

    static SwapchainSupportDetails
    Get(VkPhysicalDevice physicalDevice, VkSurfaceKHR surface)
    {
        SwapchainSupportDetails ret;

        vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, surface, &ret.capabilities);

        uint numFormats;
        uint numPresentModes;

        vkGetPhysicalDeviceSurfaceFormatsKHR     (physicalDevice, surface, &numFormats, null);
        vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface, &numPresentModes, null);

        ret.formats.length      = numFormats;
        ret.presentModes.length = numPresentModes;

        vkGetPhysicalDeviceSurfaceFormatsKHR     (physicalDevice, surface, &numFormats, ret.formats.ptr);
        vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface, &numPresentModes, ret.presentModes.ptr);

        return ret;
    }
}


VkRenderPass CreateRenderPass(
    VkDevice logicalDevice,
    VkFormat colourFormat,
    VkFormat depthFormat
)
{
    VkAttachmentDescription colourAttachment = {
        flags          : 0,
        format         : colourFormat,
        samples        : VK_SAMPLE_COUNT_1_BIT,
        loadOp         : VK_ATTACHMENT_LOAD_OP_CLEAR,
        // Clear image on load, so initialLayout doesn't matter
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

    auto depthAttachment = colourAttachment;
    depthAttachment.format      = depthFormat;
    depthAttachment.storeOp     = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    depthAttachment.finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

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
        attachmentCount : attachments.GetLengthAsUint(),
        pAttachments    : attachments.ptr,
        subpassCount    : 1,
        pSubpasses      : &subpass,
        dependencyCount : 1,
        pDependencies   : &dependency,
    };

    VkRenderPass ret;
    check!vkCreateRenderPass(logicalDevice, &createInfo, null, &ret);

    return ret;
}

/// Issue a command to update this buffer. NOTE: This cannot be performed
/// during a render pass, according to the Vulkan spec
void SendNewData(DataT)(
    VkCommandBuffer cb,
    Buffer!DataT    buffer,
    DataT[]         data
)
    in (data.length != 0)
    in (data.length * DataT.sizeof <= buffer.size)
    in (buffer.size < 65536) // vkspec pp. 832
{
    immutable VkDeviceSize dataSize = (data.length * DataT.sizeof);
    vkCmdUpdateBuffer(cb, buffer.buffer, 0, dataSize, data.ptr);
}


