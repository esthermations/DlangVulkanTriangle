module glfw_callbacks;

import bindbc.glfw;
static import globals;
import game;
import std.experimental.logger : log;

extern (C) nothrow @nogc:

void keyPressed(GLFWwindow *window, int key, int scancode, int keyAction, int) {

    auto gameAction = game.associatedAction(key);

    if (gameAction == GameAction.NO_ACTION) {
        import std.string : fromStringz;
        debug log("User pressed unbound key ",
                  glfwGetKeyName(key, scancode).fromStringz);
        return;
    }

    // Otherwise, key is bound

    auto actionIsDesired = (keyAction == GLFW_PRESS ||
                            keyAction == GLFW_REPEAT);

    Frame *frame = cast(Frame *) glfwGetWindowUserPointer(globals.window);
    frame.actionRequested[gameAction] = actionIsDesired;

    //debug log("Action ", gameAction, " => ", actionIsDesired);
}

void framebufferResized(GLFWwindow *window, int width, int height) {
    assert(width  > 0);
    assert(height > 0);

    globals.windowWidth      = width;
    globals.windowHeight     = height;
    globals.windowWasResized = true;

    //debug log("Aspect ratio is now ", globals.aspectRatio);

    Frame *frame = cast(Frame *) glfwGetWindowUserPointer(window);
    import util;
    frame.projection = util.perspective(globals.verticalFieldOfView,
                                        globals.aspectRatio,
                                        globals.nearPlane,
                                        globals.farPlane);
}

