#include <cstdio>

#define GLM_FORCE_RADIANS
#define GLM_FORCE_DEPTH_ZERO_TO_ONE
#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtx/string_cast.hpp>


void printMatrix(glm::mat4 mat) {
    for (int i = 0; i < 4; ++i) {
        for (int j = 0; j < 4; ++j) {
            printf("\t%+.3f", mat[i][j]);
        }
        printf("\n");
    }
}

int main(void) {

    constexpr auto width = 1280;
    constexpr auto height = 720;

    using namespace glm;
    mat4 view = glm::lookAt(vec3(2.0, 2.0, 2.0), vec3(0, 0, 0), vec3(0, 0, 1));
    mat4 proj = glm::perspective(glm::radians(45.0f), width / (float) height, 0.1f, 10.0f);
    proj[1][1] *= -1.0;

    //puts(glm::to_string(view).c_str());
    //puts(glm::to_string(proj).c_str());

    printf("view:\n");
    printMatrix(view);
    printf("\n");

    printf("proj:\n");
    printMatrix(proj);
    printf("\n");

    return 0;
}
