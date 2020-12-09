#/bin/sh

GLSLC=/c/VulkanSDK/1.2.154.1/Bin32/glslc.exe 


echo "Compiling shaders..."
echo "  $GLSLC" source/shader.vert -o source/vert.spv
"$GLSLC" source/shader.vert -o source/vert.spv
echo "  $GLSLC" source/shader.frag -o source/frag.spv
"$GLSLC" source/shader.frag -o source/frag.spv
echo "Done!"
