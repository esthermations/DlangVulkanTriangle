#/bin/sh

GLSLC=glslc

echo "Compiling shaders..." &&\
    echo "  $GLSLC" source/shader.vert -o source/vert.spv &&\
    "$GLSLC" source/shader.vert -o source/vert.spv &&\
    echo "  $GLSLC" source/shader.frag -o source/frag.spv &&\
    "$GLSLC" source/shader.frag -o source/frag.spv &&\
    echo "Done!"
