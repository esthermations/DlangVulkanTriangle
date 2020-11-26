import std.stdio;
import std.exception;
import erupted;
import glfw3.api;

//import platform;

void main() {

    glfwInit();
    scope (exit)
        glfwTerminate();

    enforce(glfwVulkanSupported(), "No Vulkan support from GLFW!");

    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);

    auto window = glfwCreateWindow(800, 600, "Vulkan", null, null);
    scope (exit)
        glfwDestroyWindow(window);

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
    auto glfwExtensions = glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

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
    scope(exit) vkDestroyInstance(instance, null);

    loadInstanceLevelFunctions(instance);

    // Set up debug messenger

    VkDebugUtilsMessengerEXT messenger;

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

    VkDebugUtilsMessengerCreateInfoEXT messengerCreateInfo = {
        messageSeverity : VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT | 
                          VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | 
                          VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
        messageType     : VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | 
                          VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT | 
                          VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
        pfnUserCallback : &debugCallback, 
        pUserData       : null,
    };

    immutable CreateDebugUtilsMessengerEXT = 
        cast(PFN_vkCreateDebugUtilsMessengerEXT) 
        vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");

    enforce(CreateDebugUtilsMessengerEXT !is null, 
            "Couldn't find debug messenger extension!");

    auto createMessengerResult = 
        CreateDebugUtilsMessengerEXT(instance, &messengerCreateInfo, null, 
                                     &messenger);

    enforce(createMessengerResult == VK_SUCCESS, 
            "Failed to create messenger!");

    immutable DestroyDebugUtilsMessengerEXT = 
        cast(PFN_vkDestroyDebugUtilsMessengerEXT)
        vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT");

    enforce(DestroyDebugUtilsMessengerEXT !is null, 
            "Couldn't get DestroyDebugUtilsMessengerEXT function.");

    scope(exit) DestroyDebugUtilsMessengerEXT(instance, messenger, null);

    // Create rendering surface
    VkSurfaceKHR surface;

    import glfw3.vulkan : glfwCreateWindowSurface;

    VkResult createSurfaceResult = cast(erupted.VkResult) 
        glfwCreateWindowSurface( instance, window, null, cast(ulong*)&surface);
    enforce(createSurfaceResult == VK_SUCCESS, 
            "Failed to create a window surface!");

    scope(exit) vkDestroySurfaceKHR(instance, surface, null);

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
            queueFamilyIndex : queueFamilies.graphicsFamily.get, 
            queueCount       : 1,
            pQueuePriorities : queuePriorities.ptr,
        },
    ];

    // Only append presentFamily if it's a different family to the graphics one.
    if (queueFamilies.presentFamily.get != queueFamilies.graphicsFamily.get) {
        VkDeviceQueueCreateInfo presentQueueCreateInfo = {
            queueFamilyIndex : queueFamilies.presentFamily.get,
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
    scope(exit) vkDestroyDevice(logicalDevice, null);

    loadDeviceLevelFunctions(logicalDevice);

    VkQueue graphicsQueue;
    VkQueue presentQueue;

    vkGetDeviceQueue(logicalDevice, queueFamilies.graphicsFamily.get, 0, &graphicsQueue);
    vkGetDeviceQueue(logicalDevice, queueFamilies.presentFamily.get, 0, &presentQueue);

    // Create swapchain

    SwapchainSupportDetails swapchainSupport = querySwapchainSupport(physicalDevice, surface);

    auto surfaceFormat = selectSurfaceFormat(swapchainSupport.formats);
    auto presentMode   = selectPresentMode(swapchainSupport.presentModes);
    auto extent        = selectExtent(window, swapchainSupport.capabilities);
    auto imageCount    = swapchainSupport.capabilities.minImageCount;

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
        preTransform          : swapchainSupport.capabilities.currentTransform,
        compositeAlpha        : VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        presentMode           : presentMode,
        clipped               : VK_TRUE,
        oldSwapchain          : VK_NULL_HANDLE,
    };

    VkSwapchainKHR swapchain;
    VkResult swapchainCreateResult = 
        vkCreateSwapchainKHR(logicalDevice, &swapchainCreateInfo, null, &swapchain);
    enforce(swapchainCreateResult == VK_SUCCESS, "Failed to create swapchain.");
    scope(exit) vkDestroySwapchainKHR(logicalDevice, swapchain, null);

    // Images
    
    VkImage[] swapchainImages;

    /*
    ---------------------------------------------------------------------------
    --  Main Loop
    ---------------------------------------------------------------------------
    */

    while (!glfwWindowShouldClose(window)) {
        glfwPollEvents();
    }
}

/*
-------------------------------------------------------------------------------
--  Util functions
-------------------------------------------------------------------------------
*/

import std.typecons : Nullable;

struct QueueFamilies {
    Nullable!uint graphicsFamily;
    Nullable!uint presentFamily;

    /// Are all queue families available?
    bool isComplete() {
        return !graphicsFamily.isNull && !presentFamily.isNull;
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
        if (family.queueFlags & VK_QUEUE_GRAPHICS_BIT) {
            ret.graphicsFamily = cast(uint) i;
        }

        VkBool32 supportsPresent = false;
        vkGetPhysicalDeviceSurfaceSupportKHR(physicalDevice, 
                                             cast(uint) i, 
                                             surface, 
                                             &supportsPresent);

        // Spec requires we use different queue families for graphics and present
        if (supportsPresent /*&& cast(uint) i != ret.graphicsFamily.get */) {
            ret.presentFamily = cast(uint) i;
        }

        if (ret.isComplete) {
            debug writeln("Using queues ", ret);
            return ret;
        }
    }

    enforce(ret.isComplete, "Failed to find suitable queue families.");
    return ret;
}

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
    vkEnumerateDeviceExtensionProperties(physicalDevice, null, &numExtensions, null);

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

    SwapchainSupportDetails swapchainSupport = querySwapchainSupport(physicalDevice, surface);
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

SwapchainSupportDetails querySwapchainSupport(VkPhysicalDevice physicalDevice, 
                                              VkSurfaceKHR surface) 
{
    SwapchainSupportDetails ret;

    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physicalDevice, surface, &ret.capabilities);

    uint numFormats;
    vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, &numFormats, null);
    ret.formats.length = numFormats;
    vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, &numFormats, ret.formats.ptr);

    uint numPresentModes;
    vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface, &numPresentModes, null);
    ret.presentModes.length = numPresentModes;
    vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface, &numPresentModes, ret.presentModes.ptr);

    return ret;
}

VkSurfaceFormatKHR selectSurfaceFormat(VkSurfaceFormatKHR[] availableFormats) 
    in (availableFormats.length != 0)
{
    foreach (format; availableFormats) {
        if (format.format == VK_FORMAT_B8G8R8_SRGB &&
            format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) 
        {
            return format;
        }
    }

    debug writeln("Couldn't find an ideal format, just using the first one.");
    return availableFormats[0];
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
