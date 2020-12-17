module renderer;

import std.stdio;
import std.exception : enforce;
import std.typecons : Nullable;
import std.experimental.logger;

import glfw3.api;
import gl3n.linalg;
import erupted;
import erupted.vulkan_lib_loader;

import globals;
import game;

// Extension function pointers -- these need to be loaded before called
PFN_vkCreateDebugUtilsMessengerEXT  vkCreateDebugUtilsMessengerEXT;
PFN_vkDestroyDebugUtilsMessengerEXT vkDestroyDebugUtilsMessengerEXT;

// Predefined types for Uniform and Vertex buffers

alias VertexBuffer  = Renderer.Buffer!Vertex;
alias UniformBuffer = Renderer.Buffer!Uniforms;

struct Uniforms {
    mat4 model;
    mat4 view;
    mat4 projection;
}

struct Vertex {
    vec3 position;
    vec3 normal;

    static auto getBindingDescription() {
        VkVertexInputBindingDescription ret = {
            binding   : 0,
            stride    : Vertex.sizeof,
            inputRate : VK_VERTEX_INPUT_RATE_VERTEX,
        };
        return ret;
    }

    static auto getAttributeDescription() {
        VkVertexInputAttributeDescription[2] ret = [
            {
                binding : 0,
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

struct Renderer {

    // Renderer state

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

    void render(Frame frame) {
    }

    /// Will our Vulkan instance support all the provided layers?
    bool haveAllRequiredLayers(const(char)*[] requiredLayers) pure {
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

    /// Initialise the renderer state, ready to render buffers!
    void init(VkApplicationInfo appInfo, 
              const(char)*[] requiredLayers,
              const(char)*[] requiredInstanceExtensions,
              const(char)*[] requiredDeviceExtensions) 
        in (haveAllRequiredLayers(requiredLayers))
        out (; this.logicalDevice != VK_NULL_HANDLE)
    {
        // Load initial set of Vulkan functions

        {
            bool vulkanLoadedOkay = loadGlobalLevelFunctions;
            enforce(vulkanLoadedOkay, "Failed to load Vulkan functions!");
        }

        // Glfw Extensions

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

            auto errors = vkCreateInstance(&createInfo, null, &instance);
            enforce(!errors, "Failed to create VkInstance!");
        }

        loadInstanceLevelFunctions(instance);

        // Set up debug messenger

        this.messenger = createDebugMessenger(instance);

        // Create rendering surface

        {
            import glfw3.vulkan : glfwCreateWindowSurface;
            auto errors = cast(erupted.VkResult) glfwCreateWindowSurface(
                instance, Globals.window, null, cast(ulong*)&surface);
            enforce(!errors, "Failed to create a window surface!");
        }

        // Select physical device
        
        this.physicalDevice = selectPhysicalDevice(
            this.instance, requiredDeviceExtensions, this.surface);

        // Create the logical device

        {
            QueueFamilies queueFamilies = selectQueueFamilies(this.physicalDevice, this.surface);
            enforce(queueFamilies.isComplete);

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

        // Get device queues

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
                flags            : 0,
            };

            auto errors = logicalDevice.vkCreateCommandPool(
                &createInfo, null, &commandPool);
            enforce(!errors, "Failed to create command pool.");
        }

        // Create swapchain
       
        this.swapchain = createSwapchain(
            this.logicalDevice,
            this.physicalDevice,
            this.getSurfaceExtent(),
        );

        // Create sync objects
        // FIXME: these now live in the Frame struct. 
        // When are they created? Per-frame?

        foreach (i; 0 .. MAX_FRAMES_IN_FLIGHT) {

            // Create image available semaphore

            {
                VkSemaphoreCreateInfo createInfo;
                auto errors = vkCreateSemaphore(
                    this.logicalDevice, &createInfo, null, 
                    &this.imageAvailableSemaphores[i]);
                enforce(!errors);
            }

            // Create render finished semaphore

            {
                VkSemaphoreCreateInfo createInfo;
                auto errors = vkCreateSemaphore(
                    this.logicalDevice, &createInfo, null, 
                    &this.renderFinishedSemaphores[i]);
                enforce(!errors);
            }
       }

    } // end init()

    VkDebugUtilsMessengerEXT createDebugMessenger(VkInstance instance) {
        extern (Windows) VkBool32 
        debugCallback(VkDebugUtilsMessageSeverityFlagBitsEXT      messageSeverity,
                      VkDebugUtilsMessageTypeFlagsEXT             messageType,
                      const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData, 
                      void*                                       pUserData) 
                      nothrow @nogc 
        {
            import core.stdc.stdio : printf, fflush, stdout;

            printf("validation layer: %s\n", pCallbackData.pMessage);
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
            instance, &createInfo, null, &ret);
        enforce(!createErrors, "Failed to create messenger!");

        return ret;
    }


    VkSwapchainKHR 
    createSwapchain(VkDevice          logicalDevice,
                    VkPhysicalDevice  physicalDevice, 
                    VkSurfaceKHR      surface, 
                    GLFWwindow       *window)
    {
        SwapchainSupportDetails support = querySwapchainSupport(physicalDevice, surface);

        immutable surfaceFormat = selectSurfaceFormat(support.formats);
        immutable presentMode   = selectPresentMode(support.presentModes);
        immutable extent        = selectExtent(window, support.capabilities);
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
        auto errors = vkCreateImageView(logicalDevice, &createInfo, null, &ret);
        enforce(!errors, "Failed to create an image view.");

        return ret;
    }

    VkImageView[] createImageViewsForSwapchain(VkDevice          logicalDevice,                                
                                               VkPhysicalDevice  physicalDevice,
                                               VkSurfaceKHR      surface,
                                               VkSwapchainKHR    swapchain,
                                               GLFWwindow       *window) 
    {
        // Images

        uint numImages;
        VkImage[] images;

        vkGetSwapchainImagesKHR(logicalDevice, swapchain, &numImages, null);
        images.length = numImages;
        vkGetSwapchainImagesKHR(logicalDevice, swapchain, &numImages, images.ptr);

        auto support = querySwapchainSupport(physicalDevice, surface);
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

    /// Clean up a swapchain and all its dependent items. There are a lot of them.
    /// The commandPool and pipelineLayout are NOT destroyed.
    void cleanupSwapchain() {
        vkDeviceWaitIdle(logicalDevice);

        foreach (framebuffer; this.swapchain.framebuffers) {
            vkDestroyFramebuffer(this.logicalDevice, framebuffer, null);
        }

        vkFreeCommandBuffers(
            this.logicalDevice,
            this.commandPool, 
            cast(uint) this.swapchain.commandBuffers.length, 
            this.swapchain.commandBuffers.ptr
        );

        vkDestroyPipeline(this.logicalDevice, this.swapchain.pipeline, null);

        vkDestroyRenderPass(
            this.logicalDevice, this.swapchain.renderPass, null);

        foreach (buf; swapchain.uniformBuffers) {
            vkDestroyBuffer(this.logicalDevice, buf.buffer, null);
            vkFreeMemory(this.logicalDevice, buf.memory, null);
        }

        vkDestroyDescriptorPool(
            this.logicalDevice, this.swapchain.descriptorPool, null);

        foreach (view; this.swapchain.imageViews) {
            vkDestroyImageView(this.logicalDevice, view, null);
        }

        vkDestroyImageView(
            this.logicalDevice, this.swapchain.depthResources.imageView, null);
        vkDestroyImage(
            this.logicalDevice, this.swapchain.depthResources.image, null);
        vkFreeMemory(
            this.logicalDevice, this.swapchain.depthResources.memory, null);

        vkDestroySwapchainKHR(
            this.logicalDevice, this.swapchain.swapchain, null);
    }

    struct SwapchainWithDependents {
        VkSwapchainKHR    swapchain;
        VkImageView[]     imageViews;
        VkFramebuffer[]   framebuffers;
        VkCommandBuffer[] commandBuffers;
        VkDescriptorSet[] descriptorSets;
        Buffer!Uniforms[] uniformBuffers;
        VkRenderPass      renderPass;
        VkDescriptorPool  descriptorPool;
        DepthResources    depthResources;
        VkPipeline        pipeline;

        invariant {
            assert(imageViews.length == framebuffers.length);
            assert(imageViews.length == commandBuffers.length);
            assert(imageViews.length == descriptorSets.length);
            assert(imageViews.length == uniformBuffers.length);
        }

        ulong numFramebuffers() immutable {
            return framebuffers.length;
        }
    }

    SwapchainWithDependents createSwapchainWithDependents() {
        SwapchainWithDependents ret;

        vkDeviceWaitIdle(logicalDevice);

        const colourFormat = getSurfaceFormat(this.physicalDevice, this.surface);
        const depthFormat  = VK_FORMAT_D32_SFLOAT;
        const extent = getSurfaceExtent(this.physicalDevice, surface, Globals.window);

        ret.swapchain      = this.createSwapchain();
        ret.imageViews     = this.createImageViewsForSwapchain(ret.swapchain);
        ret.uniformBuffers = this.createUniformBuffers(ret.imageViews.length);
        ret.renderPass     = this.createRenderPass(colourFormat, depthFormat);
        ret.pipeline       = this.createGraphicsPipeline(pipelineLayout, extent, ret.renderPass);
        ret.depthResources = this.createDepthResources(physicalDevice, extent);
        ret.framebuffers   = this.createFramebuffers(ret.imageViews, ret.depthResources.imageView, ret.renderPass, extent);
        ret.commandBuffers = this.createCommandBuffers(ret.framebuffers, commandPool);
        ret.descriptorPool = this.createDescriptorPool(); 
        ret.descriptorSets = this.createDescriptorSets(ret.descriptorPool, descriptorSetLayout, ret.uniformBuffers);

        return ret;
    }

    SwapchainWithDependents recreateSwapchain() {
        vkDeviceWaitIdle(this.logicalDevice);
        this.cleanupSwapchain();
        return createSwapchainWithDependents();
    }

    /// Create a command buffer for each given framebuffer.
    VkCommandBuffer[] createCommandBuffers(VkDevice        logicalDevice, 
                                           VkFramebuffer[] framebuffers, 
                                           VkCommandPool   commandPool) 
    {
        immutable numCommandBuffers = framebuffers.length;
        VkCommandBuffer[] ret;
        ret.length = numCommandBuffers;

        VkCommandBufferAllocateInfo allocateInfo = {
            commandPool        : commandPool,
            level              : VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            commandBufferCount : cast(uint) numCommandBuffers,
        };

        auto errors = 
            logicalDevice.vkAllocateCommandBuffers(&allocateInfo, ret.ptr);
        enforce(!errors, "Failed to create Command Buffers");

        return ret;
    }

    /// Create a framebuffer for each provided vkImageView.
    VkFramebuffer[] createFramebuffers(VkDevice      logicalDevice, 
                                       VkImageView[] imageViews, 
                                       VkImageView   depthImageView,
                                       VkRenderPass  renderPass,
                                       VkExtent2D    extent)
    {
        VkFramebuffer[] ret;
        ret.length = imageViews.length;

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
                logicalDevice.vkCreateFramebuffer(&createInfo, null, &ret[i]);
            enforce(!errors, "Failed to create a framebuffer.");
        }

        return ret;
    }

    VkExtent2D getSurfaceExtent() {
        const support = querySwapchainSupport();
        return selectExtent(Globals.window, support.capabilities);
    }

    /// Set up the graphics pipeline for our application. There are a lot of
    /// hardcoded properties about our pipeline in this function -- it's not nearly
    /// as agnostic as it may appear.
    VkPipeline createGraphicsPipeline(VkPipelineLayout pipelineLayout,
                                      VkExtent2D       swapchainExtent,
                                      VkRenderPass     renderPass)
    {
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

        auto bindingDescription    = Vertex.getBindingDescription;
        auto attributeDescriptions = Vertex.getAttributeDescription;

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

        /// NOTE that our viewport is flipped upside-down so we can use Y-up,
        /// where Vulkan normally uses Y-down.
        VkViewport viewport = {
            x        : 0.0f,
            y        : swapchainExtent.height,
            width    : swapchainExtent.width,
            height   : -1.0f * swapchainExtent.height,
            minDepth : 0.0f,
            maxDepth : 1.0f,
        };

        VkRect2D scissor = {
            offset : {0, 0},
            extent : swapchainExtent,
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

    /// FIXME this should probably return a VkSurfaceFormatKHR.
    VkFormat getSurfaceFormat(VkPhysicalDevice physicalDevice, 
                              VkSurfaceKHR     surface) 
    {
        auto support = querySwapchainSupport(physicalDevice, surface);
        return selectSurfaceFormat(support.formats).format;
    }

    VkRenderPass createRenderPass(VkDevice logicalDevice,
                                  VkFormat colourFormat,
                                  VkFormat depthFormat) 
    {

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

    /*
    -------------------------------------------------------------------------------
    --  selectQueueFamilies
    -------------------------------------------------------------------------------
    */

    struct QueueFamilies {
        Nullable!uint graphics;
        Nullable!uint present;
        Nullable!uint transfer;

        /// Are all queue families available?
        bool isComplete() {
            return !graphics.isNull && !present.isNull;
        }
    }

    /// Select queue families that meet our criteria, defined in this function.
    /// The members of QueueFamilies are nullable -- this function may fail to
    /// find all the queue families in that struct. If it can't find them, they
    /// will be null.
    QueueFamilies selectQueueFamilies(VkPhysicalDevice physicalDevice, 
                                      VkSurfaceKHR     surface) 
    {
        VkQueueFamilyProperties[] queueFamilies;
        uint queueFamilyCount = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, 
                                                 &queueFamilyCount, 
                                                 null);
        queueFamilies.length = queueFamilyCount;
        vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, 
                                                 &queueFamilyCount, 
                                                 queueFamilies.ptr);

        QueueFamilies ret;

        debug log("Queue families: ", queueFamilies);

        foreach (i, family; queueFamilies) {
            auto supportsGraphics = family.queueFlags & VK_QUEUE_GRAPHICS_BIT;

            if (supportsGraphics) {
                ret.graphics = cast(uint) i;
            }

            VkBool32 supportsPresent = false;
            vkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice, 
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
                debug log("Using queues ", ret);
                return ret;
            }
        }

        enforce(ret.isComplete, "Failed to find suitable queue families.");
        return ret;
    }

    /// Is this device suitable for our purposes?
    bool isSuitable(VkPhysicalDevice physicalDevice, 
                    const(char)*[]   requiredDeviceExtensions,
                    VkSurfaceKHR     surface) 
    {
        // Confirm device is a discrete GPU
        VkPhysicalDeviceProperties deviceProperties;
        vkGetPhysicalDeviceProperties(physicalDevice, &deviceProperties);

        if (deviceProperties.deviceType != VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
            return false;
        }

        // Confirm device supports our desired queue families
        QueueFamilies families = selectQueueFamilies(physicalDevice, surface);
        if (!families.isComplete) {
            return false;
        }

        // Confirm device supports our desired device extensions
        uint numExtensions;
        vkEnumerateDeviceExtensionProperties(
            physicalDevice, null, &numExtensions, null);

        VkExtensionProperties[] availableDeviceExtensions;
        availableDeviceExtensions.length = numExtensions;
        vkEnumerateDeviceExtensionProperties(physicalDevice, 
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

        SwapchainSupportDetails swapchainSupport = 
            querySwapchainSupport(physicalDevice, surface);
        swapchainSuitable = swapchainSupport.formats.length      != 0 && 
                            swapchainSupport.presentModes.length != 0;

        if (!swapchainSuitable) {
            return false;
        }

        return true;
    }

    /// Select a physical device available in the instance based on whether it
    /// satisfies isSuitable().
    VkPhysicalDevice selectPhysicalDevice(VkInstance     instance,
                                          const(char)*[] requiredDeviceExtensions,
                                          VkSurfaceKHR   surface) 
    {
        uint numPhysicalDevices;
        vkEnumeratePhysicalDevices(instance, &numPhysicalDevices, null);
        enforce(numPhysicalDevices > 0, "Couldn't find any devices!!");

        VkPhysicalDevice[] physicalDevices;
        physicalDevices.length = numPhysicalDevices;
        vkEnumeratePhysicalDevices(instance, &numPhysicalDevices, 
                                   physicalDevices.ptr);

        foreach (physicalDevice; physicalDevices) {
            if (physicalDevice.isSuitable(requiredDeviceExtensions, surface)) {
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

    SwapchainSupportDetails querySwapchainSupport() {
        SwapchainSupportDetails ret;

        vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
            this.physicalDevice, this.surface, &ret.capabilities);

        uint numFormats;
        vkGetPhysicalDeviceSurfaceFormatsKHR(
            this.physicalDevice, this.surface, &numFormats, null);
        ret.formats.length = numFormats;
        vkGetPhysicalDeviceSurfaceFormatsKHR(
            this.physicalDevice, this.surface, &numFormats, ret.formats.ptr);

        uint numPresentModes;
        vkGetPhysicalDeviceSurfacePresentModesKHR(
            this.physicalDevice, this.surface, &numPresentModes, null);
        ret.presentModes.length = numPresentModes;
        vkGetPhysicalDeviceSurfacePresentModesKHR(
            this.physicalDevice, 
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

    /**
    -------------------------------------------------------------------------------
    --  selectPresentMode
    -------------------------------------------------------------------------------
    */

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

    /*
    ---------------------------------------------------------------------------
    --  Buffers
    ---------------------------------------------------------------------------
    */

    struct Buffer(DataT) {
        VkBuffer       buffer;
        VkDeviceMemory memory;
        ulong          size; /// The size in bytes of the buffer's storage

        uint elementCount() immutable {
            return this.size / DataT.sizeof;
        }

        void cleanup() {
            vkDestroyBuffer(logicalDevice, buffer.buffer, null);
            vkFreeMemory(logicalDevice, buffer.memory, null);
        }
    }

    Buffer!T createBuffer(T)(VkBufferUsageFlags    bufferUsage, 
                             VkMemoryPropertyFlags memoryProperties)
    {
        Buffer!T ret;
        ret.size = data.length * T.sizeof;

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

        debug log("Returning buffer ", ret);
        return ret;
    }

    /// Perform a render pass (vkCmdBeginRenderPass) using the contents of this
    /// buffer, issuing commands into the provided command buffer.
    void issueRenderCommands(DataT)(immutable Buffer!DataT buffer, 
                                    VkCommandBuffer commandBuffer) 
    {

            // FIXME, which framebuffer should we use?
            immutable framebufferIndex = 0;

            // Start a render pass
            VkRenderPassBeginInfo info = {
                renderPass  : this.swapchain.renderPass,
                framebuffer : this.swapchain.framebuffers[framebufferIndex], 
                renderArea  : {
                    offset : {0, 0},
                    extent : this.getSurfaceExtent(),
                },
                clearValueCount : cast(uint) Globals.clearValues.length,
                pClearValues    : Globals.clearValues.ptr,
            };

            VkBuffer[0]     buffers = [buffer];
            VkDeviceSize[0] offsets = [0];

            vkCmdBeginRenderPass(commandBuffer, &info, VK_SUBPASS_CONTENTS_INLINE);
            vkCmdBindPipeline(VK_PIPELINE_BIND_POINT_GRAPHICS, this.swapchain.pipeline);
            vkCmdBindVertexBuffers(commandBuffer, 0, 1, buffers.ptr, offsets.ptr);

            vkCmdBindDescriptorSets(
                commandBuffer, 
                VK_PIPELINE_BIND_POINT_GRAPHICS, 
                this.pipelineLayout, 
                0, 
                1, 
                &this.swapchain.descriptorSets[framebufferIndex], 
                0, 
                null
            );

            vkCmdDraw(commandBuffer, buffer.elementCount, 1, 0, 0);
            vkCmdEndRenderPass(commandBuffer);
        }
    }

    void issueUpdateCommand(DataT)(immutable Buffer!DataT buffer, DataT[] data) 
         in (data.length != 0)
         in (data.length * DataT.sizeof <= buffer.size)
         in (this.size < 65536) // vkspec pp. 832
    {
        immutable VkDeviceSize dataSize = (data.length * DataT.sizeof);

        foreach (commandBuffer; this.swapchain.commandBuffers) {
            vkCmdUpdateBuffer(commandBuffer, buffer.buffer, 0, dataSize, data.ptr);
        }
    }

    uint findMemoryType(uint typeFilter, 
                        VkMemoryPropertyFlags requestedProperties) 
    {
        VkPhysicalDeviceMemoryProperties memProperties;
        vkGetPhysicalDeviceMemoryProperties(
            this.physicalDevice, &memProperties);

        foreach (uint i; 0 .. memProperties.memoryTypeCount) {
            immutable matchesFilter = typeFilter & (1 << i);
            alias flags = memProperties.memoryTypes[i].propertyFlags;
            immutable allPropertiesAvailable = ( flags & requestedProperties );

            if (matchesFilter && allPropertiesAvailable) {
                debug log("Using memory type ", i);
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

    DepthResources createDepthResources() {
        VkExtent2D extent = this.getSurfaceExtent();

        const format = VK_FORMAT_D32_SFLOAT;

        VkImageCreateInfo createInfo = {
            imageType     : VK_IMAGE_TYPE_2D,
            extent        : { width: extent.width, height: extent.height, depth: 1},
            mipLevels     : 1,
            arrayLayers   : 1,
            format        : format,
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
        vkGetImageMemoryRequirements(logicalDevice, image, &memoryRequirements);

        VkMemoryAllocateInfo allocInfo = {
            allocationSize  : memoryRequirements.size,
            memoryTypeIndex : findMemoryType(physicalDevice, 
                                             memoryRequirements.memoryTypeBits, 
                                             VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
        };

        VkDeviceMemory memory;
        auto allocErrors = 
            vkAllocateMemory(logicalDevice, &allocInfo, null, &memory);
        enforce(!allocErrors);

        vkBindImageMemory(logicalDevice, image, memory, 0);

        DepthResources ret = {
            image     : image,
            memory    : memory,
            imageView : createImageView(logicalDevice, image, format, 
                                        VK_IMAGE_ASPECT_DEPTH_BIT),
        };

        return ret;
    }

    VkDescriptorSet[] 
    createDescriptorSets(T)(uint count,
                            VkDescriptorPool      descriptorPool,
                            VkDescriptorSetLayout descriptorSetLayout,
                            Buffer!T[]            uniformBuffers) 
    {
        VkDescriptorSetLayout[] layouts;
        layouts.length = count;
        layouts[]      = descriptorSetLayout;

        debug log(layouts);

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

    Buffer!Uniforms[] createUniformBuffers(ulong count) 
        out(ret; ret.length == count)
    {
        Buffer[] ret;
        ret.length = count;

        foreach (i; 0 .. ret.length) {
            ret[i] = createBufferWithData!(Uniforms)(
                VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, 
                ( VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | 
                  VK_MEMORY_PROPERTY_HOST_COHERENT_BIT )
            );
        }

        return ret;
    }

    /// Clean up all Vulkan state, ready to shut down the application. Or recreate
    /// the entire Vulkan context. Or whatever.
    void cleanup() {
        cleanupSwapchain();
        vkDestroyCommandPool(logicalDevice, commandPool, null);
        vkDestroyPipelineLayout(logicalDevice, pipelineLayout, null);

        vkDestroyDescriptorPool(logicalDevice, descriptorPool, null);

        vkDestroyDescriptorSetLayout(logicalDevice, descriptorSetLayout, null);

        foreach (semaphore; allSemaphores) {
            vkDestroySemaphore(logicalDevice, semaphore, null);
        }

        foreach (fence; allFences) {
            vkDestroyFence(logicalDevice, fence, null);
        }

        vkDestroyDevice(logicalDevice, null);

        vkDestroyDebugUtilsMessengerEXT(instance, messenger, null);

        vkDestroySurfaceKHR(instance, surface, null);
        vkDestroyInstance(instance, null);
    }

} // end struct Renderer
