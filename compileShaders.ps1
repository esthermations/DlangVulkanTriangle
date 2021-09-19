$GLSLC = "C:/VulkanSDK/1.2.154.1/Bin32/glslc.exe"
Write-Output "Compiling shaders..."
Write-Output "  $GLSLC source/shader.vert -o source/vert.spv"
& "$GLSLC" source/shader.vert -o source/vert.spv
Write-Output "  $GLSLC source/shader.frag -o source/frag.spv"
& "$GLSLC" source/shader.frag -o source/frag.spv
Write-Output "Done!"
