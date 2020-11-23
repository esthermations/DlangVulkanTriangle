import std.stdio;
import std.exception;
import erupted;
import glfw3.api;

//import platform;

void main() {

	glfwInit();
	scope(exit) glfwTerminate();
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
	auto vulkan_loaded_okay = loadGlobalLevelFunctions;
	enforce(vulkan_loaded_okay);

	VkApplicationInfo appInfo;
	appInfo.pApplicationName = "Hello Triangle";
	appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
	appInfo.pEngineName = "No Engine";
	appInfo.engineVersion = VK_MAKE_VERSION(1, 0, 0);
	appInfo.apiVersion = VK_API_VERSION_1_0;
	
	VkInstanceCreateInfo createInfo;
	createInfo.pApplicationInfo = &appInfo;

	uint glfwExtensionCount;
	auto glfwExtensions = glfwGetRequiredInstanceExtensions(&glfwExtensionCount);

	createInfo.enabledExtensionCount = glfwExtensionCount;
	createInfo.ppEnabledExtensionNames = glfwExtensions;
	createInfo.enabledLayerCount = 0;

	VkInstance instance;
	auto instance_created_okay = vkCreateInstance(&createInfo, null, &instance);
	enforce(instance_created_okay == VK_SUCCESS);
	scope(exit) vkDestroyInstance(instance, null);

	// Pick physical device

	VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;

	uint deviceCount;
	vkEnumeratePhysicalDevices(instance, &deviceCount, null);
	enforce(deviceCount == 1);

	VkPhysicalDevice[] devices;
	devices.length = deviceCount;
	vkEnumeratePhysicalDevices(instance, &deviceCount, devices.ptr);

	physicalDevice = devices[0];

	VkPhysicalDeviceProperties deviceProperties;
	vkGetPhysicalDeviceProperties(physicalDevice, &deviceProperties);

	enforce(deviceProperties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU);

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
