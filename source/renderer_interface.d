module renderer_interface;

// Just importing types
import game : Frame;


/// Used to identify a frame to the renderer. FIXME: This is used directly as
/// the image index in the Vulkan swapchain. It may not survive the
/// implementation of a different render backend.
alias FrameId = uint;


interface Renderer {


    /// Create a window and get the renderer ready to draw buffers!
    void initWindow(string windowName, size_t uniformBufferSize, size_t vertexSize)
        in  (!rendererIsInitialised())
        out (; rendererIsInitialised())
        ;


    /// Intended to signal whether or not the renderer is in a functioning
    /// state for the rest of the functions in this interface.
    bool rendererIsInitialised() const;


    /**
        Return the number of valid FrameIds that this renderer supports. This
        gives the upper bound on the FrameId type - [0, numFrameIds).
    */
    uint numFrameIds() const
        in  (rendererIsInitialised())
        ;


    /// Acquire ownership of the imageIndex for the next frame.
    FrameId acquireNextFrameId()
        in  (rendererIsInitialised())
        out (fid; fid >= 0 && fid < numFrameIds())
        ;


    interface Buffer {
        /// Return the size of this buffer in bytes.
        uint sizeInBytes() const;
    }


    Buffer createVertexBuffer(size_t sizeInBytes)
        in  (rendererIsInitialised())
        out (b; b.sizeInBytes() == sizeInBytes)
        ;


    /// Set the data in this buffer to the given value.
    void setData(FrameId fid, Buffer buf, ubyte[] data)
        in (data.sizeof <= buf.sizeInBytes())
        in (getFrameState(fid) == Renderer.FrameState.RECORDING)
        ;


    void drawVertexBuffer(FrameId fid, Buffer vbuf, uint numInstances = 1)
        in  (rendererIsInitialised())
        in  (getFrameState(fid) == Renderer.FrameState.RECORDING)
        ;


    /**
        This is just modelled after Vulkan's command buffer state transitions.
    */
    enum FrameState {
        /// Frame is ready to begin recording.
        INITIAL,
        /// Frame is accepting commands.
        RECORDING,
        /// Frame has finished recording commands but those commands have not
        /// yet been sent to the GPU.
        FINISHED_RECORDING,
        /// Frame's commands have been submitted to the GPU, but we can't be
        /// certain that the GPU has finished them yet.
        SUBMITTED,
    }


    /// Get the FrameState for the given frame.
    FrameState getFrameState(FrameId fid) const
        in  (rendererIsInitialised())
        ;


    /// Reset the renderer state for this frame and get ready to receive
    /// rendering commands.
    void beginCommandsForFrame(FrameId fid, ubyte[] uniformData)
        in  (rendererIsInitialised())
        in  (  getFrameState(fid) == FrameState.INITIAL)
        out (; getFrameState(fid) == FrameState.RECORDING)
        ;


    /// Indicate that we are finished recording rendering commands for this
    /// frame, and the command buffer may be submitted.
    void endCommandsForFrame(FrameId fid)
        in  (rendererIsInitialised())
        in  (  getFrameState(fid) == FrameState.RECORDING)
        out (; getFrameState(fid) == FrameState.FINISHED_RECORDING)
        ;


    /**
        Render (present) the given frame. FIXME: What this function does  is
        specific to the Frame struct, writing a different program with this
        renderer will require revisiting this function.
    */
    void render(FrameId fid)
        in  (rendererIsInitialised())
        in  (  getFrameState(fid) == FrameState.FINISHED_RECORDING)
        out (; getFrameState(fid) == FrameState.SUBMITTED)
        ;


    /// Stall until the given frame has finished all its commands and the
    /// FrameId is ready to re-use.
    void awaitFrameCompletion(FrameId fid)
        in  (rendererIsInitialised())
        in  (  getFrameState(fid) == FrameState.SUBMITTED)
        out (; getFrameState(fid) == FrameState.INITIAL)
        ;


}
