# DlangVulkanTriangle

![](https://img.shields.io/badge/-D-ba595e) 
![](https://img.shields.io/badge/-Vulkan-AA2222)

This here is a 3D game (and engine) I'm working on over on my stream
(https://twitch.tv/esthermations). It actually renders more than triangles,
eheh. I just haven't thought of a name yet.

I'm using this project to learn Vulkan, and by proxy many of the ins and outs of
the graphics pipeline. It's been great fun so far, but please note the Vulkan
API usage is probably really inefficient here!

A goal of mine is high-performance handling of gajillions of entities, as the
game concept will take place in an asteroid field. To that end, the game uses a
(currently single-threaded) entity-component-system and I've been trying to
write it in a data-oriented way from the get-go.

The engine handles Frames, and provides a `tick()` function which produces a
frame given the previous frame (in future I may provide a `deltaTime` argument
there too). A completed Frame is handed off to the renderer to be rendered.

