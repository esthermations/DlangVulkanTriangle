import std.stdio;
import std.exception;
import erupted;
import glfw3.api;

//import platform;

void main() {

	glfwInit();
	
	glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
	glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);

	auto window = glfwCreateWindow(800, 600, "Vulkan", null, null);


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

	/*
	---------------------------------------------------------------------------
	--  Instance creation
	---------------------------------------------------------------------------
	*/
	
	VkInstanceCreateInfo createInfo;
	createInfo.pApplicationInfo = &appInfo;

	// GLFW extensions

	uint glfwExtensionCount;
	auto glfwExtensions = glfwGetRequiredInstanceExtensions(&glfwExtensionCount);
	createInfo.enabledExtensionCount = glfwExtensionCount;
	createInfo.ppEnabledExtensionNames = glfwExtensions;


	// Validation layers!!

	uint layerCount;
	vkEnumerateInstanceLayerProperties(&layerCount, null);
	enforce(layerCount > 0, "No layers available? This is weird.");

	VkLayerProperties[] availableLayers;
	availableLayers.length = layerCount;
	vkEnumerateInstanceLayerProperties(&layerCount, availableLayers.ptr);

	"Available layers:".writeln;
	foreach (layer; availableLayers) {
		layer.layerName.writeln;
	}
	"================".writeln;


	const requiredLayers = [
		"VK_LAYER_LUNARG_standard_validation"
	];

	foreach (requiredLayer; requiredLayers) {
		import std.algorithm.searching : canFind;
		foreach (layer; availableLayers) {
			writeln("Checking layer " ~ layer.layerName);
			if (layer.layerName == requiredLayer) {
				writeln("Found it!");
				break;
			} else {
				writeln("Not it.");
			}
		}
		//enforce(availableLayers.canFind!( l => l.layerName == requiredLayer),
				//"Couldn't find required layer " ~ requiredLayer);
	}

	createInfo.enabledLayerCount = cast(uint) requiredLayers.length;
	createInfo.ppEnabledLayerNames = cast(const(char)**) &requiredLayers;

	VkInstance instance;
	auto instance_created_okay = vkCreateInstance(&createInfo, null, &instance);
	enforce(instance_created_okay == VK_SUCCESS);

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

	vkDestroyInstance(instance, null);
	glfwDestroyWindow(window);
	glfwTerminate();

	return;
}
