module util;

import std.stdio;
import std.exception : enforce;
import std.typecons : Nullable;
import std.experimental.logger;

import glfw3.api;
import gl3n.linalg;
import erupted;

import globals;

/**
    Utility functions for the game engine, currently mostly Vulkan-related.
*/

void printMatrix(mat4 mat, bool rowMajor = true) {
    for (int i = 0; i < 4; ++i) {
        for (int j = 0; j < 4; ++j) {
            writef("\t%+.3f", rowMajor ? mat[j][i] : mat[i][j]);
        }
        writeln;
    }
}

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
void cleanupSwapchain(VkDevice                logicalDevice,
                      VkPipelineLayout        pipelineLayout,
                      VkCommandPool           commandPool,
                      SwapchainWithDependents swapchain) 
{
    vkDeviceWaitIdle(logicalDevice);

    foreach (framebuffer; swapchain.framebuffers) {
        logicalDevice.vkDestroyFramebuffer(framebuffer, null);
    }

    logicalDevice.vkFreeCommandBuffers(
        commandPool, 
        cast(uint) swapchain.commandBuffers.length, 
        swapchain.commandBuffers.ptr
    );

    logicalDevice.vkDestroyPipeline(swapchain.pipeline, null);
    logicalDevice.vkDestroyRenderPass(swapchain.renderPass, null);

    foreach (buf; swapchain.uniformBuffers) {
        vkDestroyBuffer(logicalDevice, buf.buffer, null);
        vkFreeMemory(logicalDevice, buf.memory, null);
    }

    vkDestroyDescriptorPool(logicalDevice, swapchain.descriptorPool, null);

    foreach (view; swapchain.imageViews) {
        logicalDevice.vkDestroyImageView(view, null);
    }

    vkDestroyImageView(logicalDevice, swapchain.depthResources.imageView, null);
    vkDestroyImage(logicalDevice, swapchain.depthResources.image, null);
    vkFreeMemory(logicalDevice, swapchain.depthResources.memory, null);

    logicalDevice.vkDestroySwapchainKHR(swapchain.swapchain, null);
}

/*
-------------------------------------------------------------------------------
--  recreateSwapchain
-------------------------------------------------------------------------------
*/

struct SwapchainWithDependents {
    VkSwapchainKHR    swapchain;
    VkImageView[]     imageViews;
    VkRenderPass      renderPass;
    VkDescriptorPool  descriptorPool;
    VkDescriptorSet[] descriptorSets;
    Buffer[]          uniformBuffers;
    DepthResources    depthResources;
    VkPipeline        pipeline;
    VkFramebuffer[]   framebuffers;
    VkCommandBuffer[] commandBuffers;
}

SwapchainWithDependents 
createSwapchain(VkDevice                 logicalDevice,
                VkPhysicalDevice         physicalDevice, 
                VkSurfaceKHR             surface, 
                GLFWwindow              *window,                        
                VkPipelineLayout         pipelineLayout,
                VkDescriptorSetLayout    descriptorSetLayout,
                VkCommandPool            commandPool)
{
    SwapchainWithDependents ret;

    vkDeviceWaitIdle(logicalDevice);

    const colourFormat = physicalDevice.getSurfaceFormat(surface);
    const depthFormat  = VK_FORMAT_D32_SFLOAT;
    const extent = physicalDevice.getSurfaceExtent(surface, window);


    ret.swapchain      = logicalDevice.createSwapchain(
        physicalDevice, surface, window);
    ret.imageViews     = logicalDevice.createImageViewsForSwapchain(
        physicalDevice, surface, ret.swapchain, window);
    ret.uniformBuffers = logicalDevice.createUniformBuffers(
        physicalDevice, ret.imageViews.length);
    ret.renderPass     = logicalDevice.createRenderPass(
        colourFormat, depthFormat);
    ret.pipeline       = logicalDevice.createGraphicsPipeline(
        pipelineLayout, extent, ret.renderPass);
    ret.depthResources = logicalDevice.createDepthResources(
        physicalDevice, extent);
    ret.framebuffers   = logicalDevice.createFramebuffers(
        ret.imageViews, ret.depthResources.imageView, ret.renderPass, extent);
    ret.commandBuffers = logicalDevice.createCommandBuffers(
        ret.framebuffers, commandPool);
    ret.descriptorPool = logicalDevice.createDescriptorPool();
    ret.descriptorSets = logicalDevice.createDescriptorSets(
        ret.descriptorPool, descriptorSetLayout, ret.uniformBuffers);

    return ret;
}

SwapchainWithDependents 
recreateSwapchain(VkDevice                 logicalDevice,
                  VkPhysicalDevice         physicalDevice, 
                  VkSurfaceKHR             surface, 
                  GLFWwindow              *window,                        
                  VkBuffer                 vertexBuffer,
                  VkPipelineLayout         pipelineLayout,
                  VkDescriptorSetLayout    descriptorSetLayout,
                  VkCommandPool            commandPool,
                  SwapchainWithDependents  oldSwapchain)
{
    vkDeviceWaitIdle(logicalDevice);
    cleanupSwapchain(logicalDevice, pipelineLayout, commandPool, oldSwapchain);
    return createSwapchain(logicalDevice, physicalDevice, surface, window, pipelineLayout, descriptorSetLayout, commandPool);
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

VkExtent2D getSurfaceExtent(VkPhysicalDevice  physicalDevice, 
                            VkSurfaceKHR      surface,
                            GLFWwindow       *window) 
{
    const support = querySwapchainSupport(physicalDevice, surface);
    return selectExtent(window, support.capabilities);
}

/// Set up the graphics pipeline for our application. There are a lot of
/// hardcoded properties about our pipeline in this function -- it's not nearly
/// as agnostic as it may appear.
VkPipeline createGraphicsPipeline(VkDevice         logicalDevice,
                                  VkPipelineLayout pipelineLayout,
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
        stageCount          : 2,
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
            //debug writeln("Using queues ", ret);
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

    //debug {
    //    import std.digest.sha;
    //    auto hash = sha256Of(data);
    //    writeln("Shader compilation: ", path, " has sha256 of ", 
    //            toHexString(hash));
    //}

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

void issueRenderCommands(ref SwapchainWithDependents swapchain,
                         in  VkExtent2D              surfaceExtent,
                             VkPipelineLayout        pipelineLayout,
                             Vertex[]                vertices,
                             VkBuffer                vertexBuffer)
{
    // Issue commands to the swapchain command buffers

    foreach (i, commandBuffer; swapchain.commandBuffers) {
        VkCommandBufferBeginInfo beginInfo;
        auto beginErrors = vkBeginCommandBuffer(commandBuffer, &beginInfo);
        enforce(!beginErrors, "Failed to begin command buffer");

        // Start a render pass
        VkRenderPassBeginInfo info = {
            renderPass  : swapchain.renderPass,
            framebuffer : swapchain.framebuffers[i],
            renderArea  : {
                offset : {0, 0},
                extent : surfaceExtent,
            },
            clearValueCount : cast(uint) Globals.clearValues.length,
            pClearValues    : Globals.clearValues.ptr,
        };

        VkBuffer[]     buffers = [vertexBuffer];
        VkDeviceSize[] offsets = [0];
        
        commandBuffer.vkCmdBeginRenderPass(&info, VK_SUBPASS_CONTENTS_INLINE);
        commandBuffer.vkCmdBindPipeline(VK_PIPELINE_BIND_POINT_GRAPHICS, swapchain.pipeline);
        commandBuffer.vkCmdBindVertexBuffers(0, 1, buffers.ptr, offsets.ptr);
        commandBuffer.vkCmdBindDescriptorSets(VK_PIPELINE_BIND_POINT_GRAPHICS, pipelineLayout, 0, 1, &swapchain.descriptorSets[i], 0, null);
        
        commandBuffer.vkCmdDraw(cast(uint) vertices.length, 1, 0, 0);

        commandBuffer.vkCmdEndRenderPass();

        auto endErrors = vkEndCommandBuffer(commandBuffer);
        enforce(!endErrors, "Failed to end command buffer.");
    }
}

struct Buffer {
    VkBuffer       buffer;
    VkDeviceMemory memory;
    ulong          size;
}

Buffer createBuffer(VkDevice              logicalDevice,
                    VkPhysicalDevice      physicalDevice,
                    ulong                 size, 
                    VkBufferUsageFlags    bufferUsage, 
                    VkMemoryPropertyFlags memoryProperties)
{
    Buffer ret;
    ret.size = size;

    // Create ret.buffer

    VkBufferCreateInfo createInfo = {
        size        : size,
        usage       : bufferUsage,
        sharingMode : VK_SHARING_MODE_EXCLUSIVE,
    };

    auto bufferCreateErrors = 
        vkCreateBuffer(logicalDevice, &createInfo, null, &ret.buffer);
    enforce(!bufferCreateErrors, "Failed to create buffer!");

    // Create ret.memory

    VkMemoryRequirements memRequirements;
    vkGetBufferMemoryRequirements(logicalDevice, ret.buffer, &memRequirements);

    VkMemoryAllocateInfo allocInfo = {
        allocationSize  : memRequirements.size,
        memoryTypeIndex : findMemoryType(physicalDevice, 
                                         memRequirements.memoryTypeBits, 
                                         memoryProperties),
    };

    auto bufferAllocErrors = 
        vkAllocateMemory(logicalDevice, &allocInfo, null, &ret.memory);
    enforce(!bufferAllocErrors, "Failed to allocate buffer!");


    auto bindErrors = vkBindBufferMemory(logicalDevice, ret.buffer, ret.memory, 0);
    enforce(!bindErrors, "Failed to bind buffer");

    debug log("Returning buffer ", ret);
    return ret;
}

   
uint findMemoryType(VkPhysicalDevice physicalDevice, 
                    uint typeFilter, 
                    VkMemoryPropertyFlags requestedProperties) 
{
    VkPhysicalDeviceMemoryProperties memProperties;
    vkGetPhysicalDeviceMemoryProperties(physicalDevice, &memProperties);

    foreach (uint i; 0 .. memProperties.memoryTypeCount) {
        immutable matchesFilter = typeFilter & (1 << i);
        immutable allPropertiesAvailable = 
            ( memProperties.memoryTypes[i].propertyFlags & 
              requestedProperties );

        if (matchesFilter && allPropertiesAvailable) {
            debug log("Using memory type ", i);
            return i;
        }
    }

    enforce(false);
    return 0;
}


void sendDataToBuffer(T)(VkDevice logicalDevice, Buffer buffer, T *data) {
    void *map;
    vkMapMemory(logicalDevice, buffer.memory, 0, buffer.size, 0, &map);
    import core.stdc.string : memcpy;
    memcpy(map, data, buffer.size);
    vkUnmapMemory(logicalDevice, buffer.memory);
}

VkDescriptorPool createDescriptorPool(VkDevice logicalDevice) {
    VkDescriptorPoolSize poolSize = {
        descriptorCount : cast(uint) Globals.uniforms.length,
    };

    VkDescriptorPoolCreateInfo createInfo = {
        poolSizeCount : 1,
        pPoolSizes    : &poolSize,
        maxSets       : cast(uint) Globals.uniforms.length,
    };

    VkDescriptorPool ret;

    auto errors = 
        vkCreateDescriptorPool(logicalDevice, &createInfo, null, &ret);
    enforce(!errors, "Failed to create a descriptor pool");

    return ret;
}

struct DepthResources {
    VkImage        image;
    VkImageView    imageView;
    VkDeviceMemory memory;
}

DepthResources createDepthResources(VkDevice         logicalDevice, 
                                    VkPhysicalDevice physicalDevice,
                                    VkExtent2D       extent) 
{

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
createDescriptorSets(VkDevice              logicalDevice, 
                     VkDescriptorPool      descriptorPool,
                     VkDescriptorSetLayout descriptorSetLayout,
                     Buffer[]              uniformBuffers) 
{
    VkDescriptorSetLayout[] layouts;
    layouts.length = Globals.uniforms.length;
    layouts[] = descriptorSetLayout;

    debug log(layouts);

    VkDescriptorSetAllocateInfo allocInfo = {
        descriptorPool : descriptorPool,
        descriptorSetCount : cast(uint) Globals.uniforms.length,
        pSetLayouts        : layouts.ptr,
    };

    VkDescriptorSet[] ret;
    ret.length = Globals.uniforms.length;

    auto errors = vkAllocateDescriptorSets(logicalDevice, &allocInfo, ret.ptr);
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

Buffer[] createUniformBuffers(VkDevice         logicalDevice, 
                              VkPhysicalDevice physicalDevice,
                              ulong            count) 
{
    Buffer[] ret;
    ret.length              = count;
    Globals.uniforms.length = count;

    foreach (i; 0 .. ret.length) {
        ret[i] = createBuffer(
            logicalDevice, 
            physicalDevice,
            Uniforms.sizeof, 
            VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT, 
            ( VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | 
              VK_MEMORY_PROPERTY_HOST_COHERENT_BIT )
        );
    }

    return ret;
}

mat4 abs(mat4 m) pure {
    import std.math : abs;
    mat4 ret;
    foreach (i; 0 .. 4) {
        foreach (j; 0 .. 4) {
            ret[i][j] = abs(m[i][j]);
        }
    }
    return ret;
}

unittest {
    mat4 m = mat4(-1);
    mat4 result = abs(m);
    assert(result == mat4(1));
}

bool approxEqual(mat4 a, mat4 b) pure {
    immutable epsilon = 0.001;
    immutable absDiff = abs(a - b);
    foreach (i; 0 .. 4) {
        foreach (j; 0 .. 4) {
            if (absDiff[i][j] > epsilon) {
                return false;
            }
        }
    }
    return true;
}

unittest {
    assert(approxEqual(mat4(1.0), mat4(1.0001)));
}

mat4 lookAt(vec3 cameraPosition, vec3 targetPosition, vec3 up) {

    vec3 normalise(vec3 v) pure {
        return v.normalized;
    }

    immutable forward = normalise(cameraPosition - targetPosition);
    immutable side    = normalise(cross(up, forward));
    immutable newUp   = normalise(cross(forward, side));

    //debug log("forward: ", forward);
    //debug log("side   : ", side);
    //debug log("newUp  : ", newUp);

    return mat4(
        side.x, newUp.x, forward.x, 0.0,
        side.y, newUp.y, forward.y, 0.0,
        side.z, newUp.z, forward.z, 0.0,
        -dot(cameraPosition, side),
        -dot(cameraPosition, newUp),
        -dot(cameraPosition, forward),
        1.0,
    );
} 

unittest {
    immutable view = lookAt(vec3(2.0, 2.0, 2.0), vec3(0, 0, 0), vec3(0, 0, 1));
    immutable expected = mat4( 
        -0.707, -0.408, +0.577, +0.000,
        +0.707, -0.408, +0.577, +0.000,
        +0.000, +0.816, +0.577, +0.000,
        -0.000, -0.000, -3.464, +1.000,
     );
    assert(approxEqual(view, expected));
}

unittest {
    immutable view = lookAt(vec3(0, 5, 0), vec3(0), vec3(1, 0, 0));
    immutable expected = mat4(
        +0.000, +0.000, +1.000, -0.000,
        +1.000, +0.000, +0.000, -0.000,
        +0.000, +1.000, +0.000, -5.000,
        +0.000, +0.000, +0.000, +1.000,
    ).transposed;
    assert(approxEqual(view, expected));
}

mat4 perspective(float top, float bottom, float left, float right, float near, float far) pure {
    immutable dx = right - left;    
    immutable dy = top - bottom;
    immutable dz = far - near;
    mat4 ret = mat4(
        2.0 * (near/dx), 0,               (right+left)/dx, 0,
        0,               2.0 * (near/dy), (top+bottom)/dy, 0,
        0,               0,               -(far+near)/dz,  -2.0*far*near/dz,
        0,               0,               -1,              0,
    );
    return ret;
}

mat4 perspective(float fovDegrees, float aspectRatio, float near, float far) pure {
    import gl3n.math : radians;
    import std.math  : tan;
    immutable top    = (near * tan(0.5 * radians(fovDegrees)));
    immutable bottom = -top;
    immutable right  = top * aspectRatio;
    immutable left   = -right;
    return perspective(top, bottom, left, right, near, far);
}

/+
mat4 perspective(float vFovDegrees, float aspectRatio, float zNear, float zFar) pure {
    import std.math  : tan, PI;
    import gl3n.math : radians;

    immutable vFov = radians(vFovDegrees);

    immutable h = 1.0 / tan(vFov / 2.0);
    immutable w = h / aspectRatio;
 
    auto ret = mat4(
        w,  0, 0,                       0,
        0, -h, 0,                       0,
        0,  0, zFar/(zNear-zFar),      -1,
        0,  0, zNear*zFar/(zNear-zFar), 0,
    );

    return ret;
}
+/

unittest {
    immutable aspectRatio = 1280.0 / 720.0;
    immutable proj = perspective(60.0, aspectRatio, 1.0, 200.0);
    immutable expected = mat4(
        +0.97428, +0.00000, +0.00000, +0.00000,
        +0.00000, +1.73205, +0.00000, +0.00000,
        +0.00000, +0.00000, -1.01005, -2.01005,
        +0.00000, +0.00000, -1.00000, +0.00000,
    );
    assert(approxEqual(proj, expected));
}

/// Clean up all Vulkan state, ready to shut down the application. Or recreate
/// the entire Vulkan context. Or whatever.
void vulkanCleanup(VkInstance                 instance,
                   VkDebugUtilsMessengerEXT   messenger,
                   VkSurfaceKHR               surface,
                   VkDevice                   logicalDevice,
                   Buffer[]                   buffers,
                   VkDescriptorSetLayout      descriptorSetLayout,
                   VkPipelineLayout           pipelineLayout,
                   VkDescriptorPool           descriptorPool,
                   VkCommandPool              commandPool,
                   SwapchainWithDependents    swapchain,
                   VkSemaphore              []allSemaphores,
                   VkFence                  []allFences) 
{
    cleanupSwapchain(logicalDevice, pipelineLayout, commandPool, swapchain);
    vkDestroyCommandPool(logicalDevice, commandPool, null);
    vkDestroyPipelineLayout(logicalDevice, pipelineLayout, null);

    foreach(buffer; buffers) {
        vkDestroyBuffer(logicalDevice, buffer.buffer, null);
        vkFreeMemory(logicalDevice, buffer.memory, null);
    }

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
