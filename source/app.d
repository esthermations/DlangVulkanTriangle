import std.stdio;
import std.exception;
import erupted;
import glfw3.api;

//import platform;

void main() {

    glfwInit();
    scope(exit) glfwTerminate();

    enforce(glfwVulkanSupported(), "No Vulkan support from GLFW!");
    
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);

    auto window = glfwCreateWindow(800, 600, "Vulkan", null, null);
    scope(exit) glfwDestroyWindow(window);


    /*
    ---------------------------------------------------------------------------
    --  Init Vulkan 
    ---------------------------------------------------------------------------
    */

    import erupted.vulkan_lib_loader;
    bool vulkanLoadedOkay = loadGlobalLevelFunctions;
    enforce(vulkanLoadedOkay, "Failed to load Vulkan functions!");

    VkApplicationInfo appInfo = {
        pApplicationName   : "Hello Triangle",
        //applicationVersion : VK_MAKE_VERSION(1, 0, 0);
        //pEngineName        : "No Engine";
        //engineVersion      : VK_MAKE_VERSION(1, 0, 0);
        apiVersion         : VK_MAKE_VERSION(1, 0, 2),
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

    import std.string : toStringz;
    const(char*)[] requiredLayers = [
        "VK_LAYER_KHRONOS_validation".toStringz
    ];

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
    auto instanceCreatedOkay = vkCreateInstance(&instanceCreateInfo, null, &instance);
    enforce(instanceCreatedOkay == VK_SUCCESS,
             "Failed to create VkInstance!");
    scope(exit) vkDestroyInstance(instance, null);

    loadInstanceLevelFunctions(instance);

    // Set up debug messenger

    VkDebugUtilsMessengerEXT messenger;

    extern(Windows) VkBool32 
    debugCallback( VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity,
                   VkDebugUtilsMessageTypeFlagsEXT messageType,
                   const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData,
                   void *pUserData ) nothrow @nogc
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

    immutable CreateDebugUtilsMessengerEXT = cast(PFN_vkCreateDebugUtilsMessengerEXT) 
        vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");
    enforce(CreateDebugUtilsMessengerEXT !is null, 
            "Couldn't find debug messenger extension!");

    auto createMessengerResult = 
        CreateDebugUtilsMessengerEXT(instance, &messengerCreateInfo, null, &messenger);

    enforce(createMessengerResult == VK_SUCCESS, "Failed to create messenger!");

    // Pick physical device

    VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;

    uint deviceCount;
    vkEnumeratePhysicalDevices(instance, &deviceCount, null);
    enforce(deviceCount > 0, "Couldn't find any devices!!");

    VkPhysicalDevice[] devices;
    devices.length = deviceCount;
    vkEnumeratePhysicalDevices(instance, &deviceCount, devices.ptr);

    physicalDevice = devices[0];

    VkPhysicalDeviceProperties deviceProperties;
    vkGetPhysicalDeviceProperties(physicalDevice, &deviceProperties);

    enforce(deviceProperties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU,
            "Device isn't a discrete GPU!");

    // Logical device
    VkDevice device;

    // Select a queue family

    VkQueueFamilyProperties[] queueFamilies;

    uint queueFamilyCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, null);
    queueFamilies.length = queueFamilyCount;
    vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, queueFamilies.ptr);

    uint queueFamilyIndex;
    foreach (i, family; queueFamilies) {
        if (family.queueFlags & VK_QUEUE_GRAPHICS_BIT) {
            queueFamilyIndex = cast(uint) i;
            writeln("Using queue ", i, " = ", family);
            std.stdio.stdout.flush;
            break;
        }
    }

    float queuePriority = 1.0;

    VkDeviceQueueCreateInfo queueCreateInfo = {
        queueFamilyIndex : queueFamilyIndex, 
        queueCount       : 1,
        pQueuePriorities : &queuePriority,
    };

    // Device features
    VkPhysicalDeviceFeatures deviceFeatures;

    writeln(deviceFeatures);
    std.stdio.stdout.flush;

    VkDeviceCreateInfo deviceCreateInfo = {
        pQueueCreateInfos     : &queueCreateInfo,
        queueCreateInfoCount  : 1,
        pEnabledFeatures      : &deviceFeatures,
    };

    auto deviceCreatedOkay = vkCreateDevice(physicalDevice, &deviceCreateInfo, null, &device);
    enforce(deviceCreatedOkay == VK_SUCCESS, "Failed to create VkDevice!");
    scope(exit) vkDestroyDevice(device, null);

    VkQueue queue;

    "About to call vkGetDeviceQueue".writeln;
    std.stdio.stdout.flush;
    vkGetDeviceQueue(device, queueFamilyIndex, 0, &queue);
    "It worked!!".writeln; 
    std.stdio.stdout.flush;

    loadDeviceLevelFunctions(device);

    // Create rendering surface

    VkSurfaceKHR surface;

    import glfw3.vulkan : glfwCreateWindowSurface;
    VkResult createSurfaceResult = cast(erupted.VkResult)
         glfwCreateWindowSurface(instance, window, null, cast(ulong*) &surface);
    //enforce(createSurfaceResult == VK_SUCCESS, "Failed to create a window surface!");

    /*
    ---------------------------------------------------------------------------
    --  Main Loop
    ---------------------------------------------------------------------------
    */

    while (!glfwWindowShouldClose(window)) {
        glfwPollEvents();
    }

    /*
    ---------------------------------------------------------------------------
    --  Cleanup
    ---------------------------------------------------------------------------
    */
}
