module util;

import std.stdio;
import std.exception : enforce;
import std.typecons : Nullable;
import glfw3.api;
import erupted;

/**
    Utility functions for the game engine, currently mostly Vulkan-related.
*/

PFN_vkCreateDebugUtilsMessengerEXT  vkCreateDebugUtilsMessengerEXT;
PFN_vkDestroyDebugUtilsMessengerEXT vkDestroyDebugUtilsMessengerEXT;

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

VkImageView[] createImageViews(VkDevice          logicalDevice,                                
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
    auto swapchainImageFormat = selectSurfaceFormat(support.formats);
    auto swapchainExtent      = selectExtent(window, support.capabilities);

    // Image views

    VkImageView[] ret;
    ret.length = images.length;

    foreach(i, image; images) {
        VkImageViewCreateInfo createInfo = {
            image      : image,
            viewType   : VK_IMAGE_VIEW_TYPE_2D,
            format     : swapchainImageFormat,
            components : {
                r : VK_COMPONENT_SWIZZLE_IDENTITY,
                g : VK_COMPONENT_SWIZZLE_IDENTITY,
                b : VK_COMPONENT_SWIZZLE_IDENTITY,
                a : VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            subresourceRange : {
                aspectMask     : VK_IMAGE_ASPECT_COLOR_BIT,
                baseMipLevel   : 0,
                levelCount     : 1,
                baseArrayLayer : 0,
                layerCount     : 1,
            },
        };

        auto errors = vkCreateImageView(
            logicalDevice, &createInfo, null, &ret[i]);
        enforce(!errors, "Failed to create an image view.");
    }

    return ret;
}

/// Clean up a swapchain and all its dependent items. There are a lot of them.
void cleanupSwapchain(VkDevice           logicalDevice,
                      VkFramebuffer    []swapchainFramebuffers,
                      VkCommandPool      commandPool,
                      VkCommandBuffer  []commandBuffers,
                      VkPipeline         graphicsPipeline,
                      VkPipelineLayout   pipelineLayout,
                      VkRenderPass       renderPass,
                      VkImageView      []swapchainImageViews, 
                      VkSwapchainKHR     swapchain) 
{
    foreach (framebuffer; swapchainFramebuffers) {
        vkDestroyFramebuffer(logicalDevice, framebuffer, null);
    }

    vkFreeCommandBuffers(logicalDevice, commandPool, 
                         cast(uint) commandBuffers.length, commandBuffers.ptr);

    vkDestroyPipeline(logicalDevice, graphicsPipeline, null);
    vkDestroyPipelineLayout(logicalDevice, pipelineLayout, null);
    vkDestroyRenderPass(logicalDevice, renderPass, null);

    foreach (view; swapchainImageViews) {
        vkDestroyImageView(logicalDevice, view, null);
    }

    vkDestroySwapchainKHR(logicalDevice, swapchain, null);
}

/// Clean up all Vulkan state, ready to shut down the application. Or recreate
/// the entire Vulkan context. Or whatever.
void vulkanCleanup(VkInstance                 instance,
                   VkDebugUtilsMessengerEXT   messenger,
                   VkSurfaceKHR               surface,
                   VkDevice                   logicalDevice,
                   VkSwapchainKHR             swapchain,
                   VkImageView              []swapchainImageViews,
                   VkFramebuffer            []swapchainFramebuffers,
                   VkCommandBuffer          []commandBuffers,
                   VkCommandPool              commandPool,
                   VkRenderPass               renderPass,
                   VkPipeline                 graphicsPipeline,
                   VkPipelineLayout           pipelineLayout,
                   VkSemaphore              []allSemaphores,
                   VkFence                  []allFences) 
{
    cleanupSwapchain(logicalDevice, 
                     swapchainFramebuffers, 
                     commandPool, 
                     commandBuffers, 
                     graphicsPipeline, 
                     pipelineLayout, 
                     renderPass, 
                     swapchainImageViews, 
                     swapchain);

    foreach (semaphore; allSemaphores) {
        vkDestroySemaphore(logicalDevice, semaphore, null);
    }

    foreach (fence; allFences) {
        vkDestroyFence(logicalDevice, fence, null);
    }

    vkDestroyCommandPool(logicalDevice, commandPool, null);
    vkDestroyDevice(logicalDevice, null);

    vkDestroyDebugUtilsMessengerEXT(instance, messenger, null);

    vkDestroySurfaceKHR(instance, surface, null);
    vkDestroyInstance(instance, null);
}

/*
-------------------------------------------------------------------------------
--  recreateSwapchain
-------------------------------------------------------------------------------
*/

VkSwapchainKHR recreateSwapchain(VkDevice           logicalDevice,
                                 VkPhysicalDevice   physicalDevice, 
                                 VkSurfaceKHR       surface, 
                                 GLFWwindow        *window,                        
                                 VkFramebuffer    []swapchainFramebuffers,                        
                                 VkCommandPool      commandPool,                        
                                 VkCommandBuffer  []commandBuffers,                        
                                 VkPipeline         graphicsPipeline,                        
                                 VkPipelineLayout   pipelineLayout,                        
                                 VkRenderPass       renderPass,                        
                                 VkImageView      []swapchainImageViews,                         
                                 VkSwapchainKHR     swapchain) 
{
    vkDeviceWaitIdle(logicalDevice);

    cleanupSwapchain(logicalDevice, 
                     swapchainFramebuffers, 
                     commandPool,  // FIXME: I want to hang on to the command pool in this case.
                     commandBuffers, 
                     graphicsPipeline, 
                     pipelineLayout, 
                     renderPass, 
                     swapchainImageViews, 
                     swapchain);

    const format = physicalDevice.getSurfaceFormat(surface);
    const extent = physicalDevice.getSurfaceExtent(surface, window);

    auto newSwapchain      = logicalDevice.createSwapchain(physicalDevice, surface, window);
    auto newImageViews     = logicalDevice.createImageViews(physicalDevice, surface, newSwapchain, window);
    auto newRenderPass     = logicalDevice.createRenderPass(format);
    auto newPipeline       = logicalDevice.createGraphicsPipeline(extent, newRenderPass);
    auto newFramebuffers   = logicalDevice.createFramebuffers(newImageViews, newRenderPass, extent);
    auto newCommandBuffers = logicalDevice.createCommandBuffers(newFramebuffers, commandPool);
}

/// Create a command buffer for each given framebuffer.
VkCommandBuffer[] createCommandBuffers(VkDevice        logicalDevice, 
                                       VkFramebuffer[] framebuffers, 
                                       VkCommandPool   commandPool) 
{
    VkCommandBuffer[] ret;
    ret.length = framebuffers.length;

    VkCommandBufferAllocateInfo commandBufferAllocateInfo = {
        commandPool        : commandPool,
        level              : VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        commandBufferCount : cast(uint) commandBuffers.length,
    };

    auto errors = logicalDevice.vkAllocateCommandBuffers(
        &commandBufferAllocateInfo, ret.ptr);
    enforce(!errors, "Failed to create Command Buffers");

    return ret;
}

/// Create a framebuffer for each provided vkImageView.
VkFramebuffer[] createFramebuffers(VkDevice      logicalDevice, 
                                   VkImageView[] imageViews, 
                                   VkRenderPass  renderPass,
                                   VkExtent2D    extent)
{
    VkFramebuffer[] ret;
    ret.length = imageViews.length;

    foreach (i, view; imageViews) {
        VkImageView[1] attachments = [ view ];

        VkFramebufferCreateInfo createInfo = {
            renderPass      : renderPass,
            attachmentCount : 1,
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

VkExtent2D getSurfaceExtent(VkPhysicalDevice  physicalDevice, 
                            VkSurfaceKHR      surface,
                            GLFWwindow       *window) 
{
    const support = querySwapchainSupport(physicalDevice, surface);
    return selectExtent(window, support.capabilities);
}

VkPipeline createGraphicsPipeline(VkDevice     logicalDevice,                                    
                                  VkExtent2D   swapchainExtent,
                                  VkRenderPass renderPass)
{
    VkShaderModule vertModule = createShaderModule(logicalDevice, "./source/vert.spv"); 
    VkShaderModule fragModule = createShaderModule(logicalDevice, "./source.frag.spv");

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

    VkPipelineShaderStageCreateInfo[2] shaderStages = 
        [vertStageCreateInfo, fragStageCreateInfo];

    VkPipelineVertexInputStateCreateInfo vertexInputCreateInfo = {
        vertexBindingDescriptionCount   : 0,
        pVertexBindingDescriptions      : null,
        vertexAttributeDescriptionCount : 0,
        pVertexAttributeDescriptions    : null,
    };

    VkPipelineInputAssemblyStateCreateInfo inputAssemblyCreateInfo = {
        topology               : VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        primitiveRestartEnable : VK_FALSE,
    };

    VkViewport viewport = {
        x        : 0.0f,
        y        : 0.0f,
        width    : swapchainExtent.width,
        height   : swapchainExtent.height,
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
        frontFace               : VK_FRONT_FACE_CLOCKWISE,
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

    VkGraphicsPipelineCreateInfo createInfo = {
        stageCount          : 2,
        pStages             : shaderStages.ptr,
        pVertexInputState   : &vertexInputCreateInfo,
        pInputAssemblyState : &inputAssemblyCreateInfo,
        pViewportState      : &viewportStateCreateInfo,
        pRasterizationState : &rasterisationStateCreateInfo,
        pMultisampleState   : &multisampleStateCreateInfo,
        pDepthStencilState  : null,
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


VkFormat getSurfaceFormat(VkPhysicalDevice physicalDevice, 
                          VkSurfaceKHR     surface) 
{
    auto support = querySwapchainSupport(physicalDevice, surface);
    return selectSurfaceFormat(support.formats);
}

VkRenderPass createRenderPass(VkDevice logicalDevice,
                              VkFormat swapchainImageFormat) 
{

    VkAttachmentDescription colourAttachment = { 
        format         : swapchainImageFormat,
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

    VkSubpassDescription subpass = {
        pipelineBindPoint    : VK_PIPELINE_BIND_POINT_GRAPHICS,
        colorAttachmentCount : 1,
        pColorAttachments    : &colourAttachmentReference,
    };


    VkSubpassDependency dependency = {
        srcSubpass    : VK_SUBPASS_EXTERNAL,
        dstSubpass    : 0,
        srcStageMask  : VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        srcAccessMask : 0,
        dstStageMask  : VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        dstAccessMask : VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    };

    VkRenderPassCreateInfo createInfo = {
        attachmentCount : 1,
        pAttachments    : &colourAttachment,
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

    /// Are all queue families available?
    bool isComplete() {
        return !graphics.isNull && !present.isNull;
    }
}


/// Select queue families that meet our criteria, defined in this function. The
/// members of QueueFamilies are nullable -- this function may fail to find all
/// the queue families in that struct. If it can't find them, they will be null.
QueueFamilies selectQueueFamilies(VkPhysicalDevice physicalDevice, 
                                  VkSurfaceKHR surface) 
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
    
    foreach (i, family; queueFamilies) {
        // Select graphics family

        auto supportsGraphics = family.queueFlags & VK_QUEUE_GRAPHICS_BIT;

        if (supportsGraphics) {
            ret.graphics = cast(uint) i;
        }

        VkBool32 supportsPresent = false;
        vkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice, 
                                             cast(uint) i, 
                                             surface, 
                                             &supportsPresent);

        // NOTE: We may want to use different queue families for graphics and
        // present. Not sure why, but the tutorial said we would.
        if (supportsPresent) {
            ret.present = cast(uint) i;
        }

        if (ret.isComplete) {
            debug writeln("Using queues ", ret);
            return ret;
        }
    }

    enforce(ret.isComplete, "Failed to find suitable queue families.");
    return ret;
}

/*
-------------------------------------------------------------------------------
--  isSuitable(VkPhysicalDevice)
-------------------------------------------------------------------------------
*/

/// Is this device suitable for our purposes (drawing a triangle)?
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
    // char[256] and some things are const(char)* and some things are string.
    // That's all.

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

/*
-------------------------------------------------------------------------------
--  selectPhysicalDevice
-------------------------------------------------------------------------------
*/

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

/*
-------------------------------------------------------------------------------
--  querySwapchainSupport
-------------------------------------------------------------------------------
*/

struct SwapchainSupportDetails {
    VkSurfaceCapabilitiesKHR   capabilities;
    VkSurfaceFormatKHR       []formats;
    VkPresentModeKHR         []presentModes;
}

SwapchainSupportDetails querySwapchainSupport(VkPhysicalDevice physicalDevice, 
                                              VkSurfaceKHR surface) 
{
    SwapchainSupportDetails ret;

    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
        physicalDevice, surface, &ret.capabilities);

    uint numFormats;
    vkGetPhysicalDeviceSurfaceFormatsKHR(
        physicalDevice, surface, &numFormats, null);
    ret.formats.length = numFormats;
    vkGetPhysicalDeviceSurfaceFormatsKHR(
        physicalDevice, surface, &numFormats, ret.formats.ptr);

    uint numPresentModes;
    vkGetPhysicalDeviceSurfacePresentModesKHR(
        physicalDevice, surface, &numPresentModes, null);
    ret.presentModes.length = numPresentModes;
    vkGetPhysicalDeviceSurfacePresentModesKHR(
        physicalDevice, surface, &numPresentModes, ret.presentModes.ptr);

    return ret;
}

/*
-------------------------------------------------------------------------------
--  selectSurfaceFormat
-------------------------------------------------------------------------------
*/

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

    debug writeln("Couldn't find an ideal format, just using the first one.");
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

/**
-------------------------------------------------------------------------------
--  selectExtent
-------------------------------------------------------------------------------
*/

VkExtent2D selectExtent(   GLFWwindow              *window, 
                        in VkSurfaceCapabilitiesKHR capabilities) {
    // If width/height are set to UINT32_MAX then we're required to translate
    // the screen coordinates from GLFW to pixels and provide that size.
    if (capabilities.currentExtent.width != uint.max) {
        return capabilities.currentExtent;
    } else {
        int width, height;
        glfwGetFramebufferSize(window, &width, &height);

        import std.algorithm : clamp;

        immutable minWidth  = capabilities.minImageExtent.width;
        immutable maxWidth  = capabilities.maxImageExtent.width;
        immutable minHeight = capabilities.minImageExtent.height;
        immutable maxHeight = capabilities.maxImageExtent.height;

        VkExtent2D ret = {
            width  : cast(uint) clamp(width, minWidth, maxWidth),
            height : cast(uint) clamp(height, minHeight, maxHeight) 
        };

        return ret;
    }
}

/**
-------------------------------------------------------------------------------
--  createShaderModule
-------------------------------------------------------------------------------
*/

VkShaderModule createShaderModule(VkDevice logicalDevice, string path) {
    import std.stdio : File;
    auto file = File(path, "rb");
    auto data = file.rawRead(new uint[file.size / uint.sizeof]);

    debug {
        import std.digest.sha;
        auto hash = sha256Of(data);
        writeln("Shader compilation: ", path, " has sha256 of ", 
                toHexString(hash));
    }

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

