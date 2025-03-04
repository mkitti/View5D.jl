"""
Visualizing multiple-dimensional (ND) datasets (AbstractArrays) is important for data research and debugging of ND algorithms. `View5D.jl`  (https://github.com/RainerHeintzmann/View5D.jl) is a Java-based viewer for up to 5-dimensional data (including `Complex`). It supports three mutually linked orthogonal slicing displays for XYZ coordinates, arbitrary numbers of colors (4th `element` dimension) which can also be used to display spectral curves and a time slider for the 5th dimension.  


The Java viewer `View5D` (https://nanoimaging.de/View5D) has been integrated into julia with the help of `JavaCall.jl`.  Currently the viewer has its full Java functionality which includes displaying and interacting with 5D data. Generating up to three-dimensional histograms and interacting with them to select regions of interest in the 3D histogram but shown as a selection in the data. It allows selection of a gate `element` where thresholds can be applied to which have an effect on statistical evaluation (mean, max, min) in other `element`s if the `gate` is activated. It further supports multiplicative overlay of colors. This feature is nice when processed data (e.g. local orientation information or polarization direction or ratios) needs to be presented along with brightness data. By choosing a gray-valued and a  constant brightness value-only (HSV) colormap for brightness and orientation data respectively, in multiplicative overlay mode a result is obtained that looks like the orientation information is staining the brightness. These results look often much nicer compared to gating-based display based on a brightness-gate, which is also supported.
Color display of floating-point or 16 or higher bit data supports adaptively updating colormaps.
Zooming in on a colormap,  by changing the lower and upper display threshold, for some time the colormap is simply changed to yield a smooth experience but occasionally the cached display data is recomputed to avoid loosing fine granularity on the color levels.

`View5D` also supports displaying and interacting with tracking in 3D over time (and other combinations) datasets.  This can come in handy for single particle or cell tracking. A particularly interesting feature is that the data can be pinned (aligned) to a chosen track. 

`View5D` has 3 context menus (main panel, element view panel and general) with large range of ways to change the display. A system of equidistant location (and brightness) information (scaling and offset) is also present but not yet integrated into julia. 

The interaction to julia is currently (March 2021) at a basic level of invoking the viewer using existing data. However, it already supports a wide range of data formats: `Float32`, `Float64`, `UInt8`, `Int8`, `UInt16`, `Int16`, `UInt32`, `Int32`, `Int`.
`Complex32`, `RGB` and `Gray`

Display of `Complex`-valued data can be toggled between `magnitude`, `phase`, `real` and `imaginary` part.  A complex-valued array by default switches the viewer to a `gamma` of 0.3 easing the inspection of Fourier-transformed data. However, gamma is adjustable interactively as well as when invoking the viewer.

Since the viewer is written in Java and launched via JavaCall its thread should be pretty independent from julia. This should make the user experience pretty smooth also with minimal implications to julia threading performance. 

Current problems of `View5D` are that it is not well suited to displaying huge datasets. This is due to memory usage and the display slowing down due to on-the-fly calculations of features such as averages and the like. A further problem is that it seems very difficult to free Java memory correctly upon finalization. Even though this was not tested yet, I would expect the viewer to gradually use up memory when repeatedly invoked and closed.

Future versions will support features such as 
- retrieving user-interaction data from the viewer
- life update
- adding further elements to existing viewer(s) 

"""
module View5D
export view5d, vv, vp, vt, ve, vep, get_active_viewer
export @vv, @ve, @vp, @vep, @vt
export process_key_element_window, process_key_main_window, process_keys
export set_axis_scales_and_units, set_value_unit, set_value_name
export repaint, update_panels, to_front, hide_viewer, set_fontsize
export set_gamma, set_min_max_thresh
export set_element, set_time, set_elements_linked, set_times_linked
export set_element_name, get_num_elements, get_num_times, set_title
export set_display_size
export export_marker_lists, import_marker_lists, delete_all_marker_lists, export_markers_string
#export init_layout, invalidate 

using JavaCall
using LazyArtifacts  # used to be Pkg.artifacts
using Colors, ImageCore
# using JavaShowMethods

# In the line below dirname(@__DIR__) is absolutely crucial, otherwise strange errors appear
# in dependence of how the julia system initializes and whether you run in VScode or
# an ordinary julia REPL. This was hinted by @mkitti
# see https://github.com/JuliaInterop/JavaCall.jl/issues/139
# for details
# myPath = ["-Djava.class.path=$(joinpath(dirname(@__DIR__), "jars","View5D.jar"))"]
# print("Initializing JavaCall with callpath: $myPath\n")
# JavaCall.init(myPath)
# JavaCall.init(["-Djava.class.path=$(joinpath(@__DIR__, "jars","view5d"))"])

# const View5D_jar = joinpath(dirname(@__DIR__), "jars","View5D.jar")

# This is the proper way to do this via artifacts:
rootpath = artifact"View5D-jar"
# @show rootpath = "C:\\Users\\pi96doc\\Documents\\Programming\\Java\\View5D"
const View5D_jar = joinpath(rootpath, "View5D_v2.3.1.jar")
# my personal development version
# const View5D_jar = joinpath(rootpath, "View5D_v2.jar")

function __init__()
    # This has to be in __init__ and is invoked by `using View5D`
    # Allows other packages to addClassPath before JavaCall.init() is invoked
    JavaCall.addClassPath(View5D_jar)
end

is_complex(mat) = eltype(mat) <: Complex

# expanddims(x, ::Val{N}) where N = reshape(x, (size(x)..., ntuple(x -> 1, N)...))
expanddims(x, num_of_dims) = reshape(x, (size(x)..., ntuple(x -> 1, (num_of_dims - ndims(x)))...))

"""
    set_gamma(gamma=1.0, myviewer=nothing; element=0)

modifies the display `gamma` in myviewer
# Arguments

* `gamma`: defines how the data is displayed via `shown_value = data .^gamma`. 
        More precisely: `clip((data.-low).(high-low)) .^ gamma`
* `myviewer`: The viewer to which this gamma should be applied to. By default the active viewer is used.
* `element`: to which color channel (element) should this gamma be applied to

# Example
```jldoctest
julia> v2 = view5d(rand(Float64,6,5,4,3,1))

julia> set_gamma(0.2,element=1)
```
"""
function set_gamma(gamma=1.0, myviewer=nothing; element=0)
    myviewer=get_viewer(myviewer)
    jcall(myviewer, "SetGamma", Nothing, (jint, jdouble), element, gamma);
    update_panels(myviewer)
end

"""
    set_time(mytime=-1, myviewer=nothing)

sets the display position to mytime. A negative value means last timepoint
# Arguments

* `mytime`: The timepoint to set the viewer to
* `myviewer`: The viewer to which this function applies to. By default the active viewer is used.

# Example
```jldoctest
julia> v2 = view5d(rand(Float64,6,5,4,3,2))

julia> set_time(0) # return to the first time point
```
"""
function set_time(mytime=-1, myviewer=nothing)
    myviewer=get_viewer(myviewer)
    jcall(myviewer, "setTime", Nothing, (jint,), mytime);
    update_panels(myviewer)
    repaint(myviewer)
end

"""
    set_element(myelement=-1, myviewer=nothing)

sets the display position to mytime. A negative value means last timepoint
# Arguments

* `myelement`: The element position (color) to which the viewer display position is set to
* `myviewer`: The viewer to which this function applies to. By default the active viewer is used.

# Example
```jldoctest
julia> v2 = view5d(rand(Float64,6,5,4,3,1))

julia> set_element(0) # return to the first color channel
```
"""
function set_element(myelement=-1, myviewer=nothing)
    myviewer=get_viewer(myviewer)
    jcall(myviewer, "setElement", Nothing, (jint,), myelement);
    update_panels(myviewer)
    repaint(myviewer)
end

"""
    set_element_name(element,new_name, myviewer=nothing)
provides a new name to the `element` displayed in the viewer

# Arguments
* `element`: The element to rename
* `new_name`: The new name for the element
* `myviewer`: The viewer to apply this to. By default the active viewer is used.
"""
function set_element_name(element, new_name::String, myviewer=nothing)
    myviewer=get_viewer(myviewer)
    jcall(myviewer, "setName", Nothing, (jint, JString), element, new_name);
    update_panels(myviewer)
end

"""
    set_elements_linked(is_linked::Bool,myviewer=nothing)
provides a new name to the `element` displayed in the viewer

# Arguments
* `is_linked`: defines whether all elements are linked
* `myviewer`: The viewer to apply this to. By default the active viewer is used.
"""
function set_elements_linked(is_linked::Bool, myviewer=nothing)
    myviewer=get_viewer(myviewer)
    jcall(myviewer, "SetElementsLinked", Nothing, (jboolean,), is_linked);
    update_panels(myviewer)
end

"""
    set_times_linked(is_linked::Bool,myviewer=nothing)
    provides a new name to the `element` displayed in the viewer

# Arguments
* `is_linked`: defines whether all times are linked
* `myviewer`: The viewer to apply this to. By default the active viewer is used.
"""
function set_times_linked(is_linked::Bool, myviewer=nothing)
    myviewer=get_viewer(myviewer)
    jcall(myviewer, "setTimesLinked", Nothing, (jboolean,), is_linked);
    update_panels(myviewer)
end

"""
    set_title(title, myviewer=nothing)
sets the title of the viewer

# Arguments
* `title`: new name of the window of the viewer
* `myviewer`: The viewer to apply this to. By default the active viewer is used.
"""
function set_title(title::String, myviewer=nothing)
    myviewer=get_viewer(myviewer)
    jcall(myviewer, "NameWindow", Nothing, (JString,), title);
    update_panels(myviewer)
end

"""
    set_display_size(sx::Int,sy::Int, myviewer=nothing)
sets the size on the screen, the viewer is occupying
    
# Arguments
* `sx`: horizontal size in pixels
* `sy`: vertical size in pixels
* `myviewer`: the viewer to apply this to. By default the active viewer is used.
"""
function set_display_size(sx::Int,sy::Int, myviewer=nothing) # ; reinit=true
    myviewer=get_viewer(myviewer)
    myviewer=jcall(myviewer, "setSize", Nothing, (jint,jint),sx,sy) ;
    #if reinit
    #    process_keys("i", myviewer)  # does not work, -> panel?
    #end
end

"""
    get_num_elements(myviewer=nothing)
gets the number of currently existing elements in the viewer

# Arguments
* `myviewer`: the viewer to apply this to. By default the active viewer is used.
"""
function get_num_elements(myviewer=nothing)
    myviewer=get_viewer(myviewer)
    num_elem=jcall(myviewer, "getNumElements", jint, ());
end

"""
    set_axis_scales_and_units(pixelsize=(1.0,1.0,1.0,1.0,1.0),
        value_name = "intensity",value_unit = "photons",
        axis_names = ["X", "Y", "Z", "E", "T"],
        axis_units=["a.u.","a.u.","a.u.","a.u.","a.u."], myviewer=nothing; 
        element=0,time=0)

overwrites the units and scaling of all five axes and the value units and scalings.

# Arguments
* `pixelsize`: 5D vector of pixel sizes.
* `value_scale`: the scale of the value axis
* `value_name`: the name of the value axis of this element as a String
* `value_unit`: the unit of the value axis of this element as a String
* `axes_names`: the names of the various (X,Y,Z,E,T) axes as a 5D vector of String
* `axes_units`: the units of the various axes as a 5D vector of String

#Example
```jldoctest
julia> v1 = view5d(rand(Int16,6,5,4,2,2))

julia> set_axis_scales_and_units((1,0.02,20,1,2),20,"irradiance","W/cm^2",["position","λ","micro-time","repetition","macro-time"],["mm","µm","ns","#","minutes"],element=0)
```
"""
function set_axis_scales_and_units(pixelsize=(1.0,1.0,1.0,1.0,1.0),
    value_scale=1.0, value_name = "intensity",value_unit = "photons",
    axes_names = ["X", "Y", "Z", "E", "T"],
    axes_units=["a.u.","a.u.","a.u.","a.u.","a.u."], myviewer=nothing; 
    element=0,time=0)

    myviewer=get_viewer(myviewer)    
    # the line below set this for all elements and times
    jStringArr = Vector{JString}
    L = length(pixelsize)
    if L != 5
        @warn "pixelsize should be 5D but has only $L entries. Replacing trailing dimensions by 1.0."
        tmp=pixelsize;pixelsize=ones(5); pixelsize[1:L].=tmp[:];
    end
    L = length(axes_names)
    if L != 5
        @warn "axes_names should be 5D but has only $L entries. Replacing trailing dimensions by standard names."
        tmp=axes_names;axes_names=["X","Y","Z","E","T"]; axes_names[1:L].=tmp[:];
    end
    L = length(axes_units)
    if L != 5
        @warn "axes_units should be 5D but has only $L entries. Replacing trailing dimensions by \"a.u.\"."
        tmp=axes_units;axes_units=["a.u.","a.u.","a.u.","a.u.","a.u."]; axes_units[1:L].=tmp[:];
    end
    jcall(myviewer, "SetAxisScalesAndUnits", Nothing, (jint,jint, jdouble,jdouble,jdouble,jdouble,jdouble,jdouble,jdouble,jdouble,jdouble,jdouble,jdouble,jdouble,
            JString,jStringArr,JString,jStringArr),
            element,time, value_scale, pixelsize..., 0,0,0,0,0,0,
            value_name, axes_names, value_unit, axes_units);
    update_panels(myviewer);
    repaint(myviewer);
end

"""
    set_value_unit(unit::String="a.u.", myviewer=nothing; element::Int=0)
sets the units for the values of a particular element.

# Arguments
* `unit`: a sting with the unit name
* `myviewer`: the viewer to apply this to. By default the active viewer is used.
* `element`:  the element for which to set the unit (count starts with 0)

#see also
`set_axis_scales_and_units`, `set_value_name`
"""
function set_value_unit(unit::String="a.u.", myviewer=nothing; element::Int=0)
    myviewer=get_viewer(myviewer)
    jcall(myviewer, "setUnit", Nothing, (jint, JString), element, unit);
    repaint()
end

"""
    set_value_name(name::String="intensity", myviewer=nothing; element::Int=0)
sets the name for the values of a particular element.

# Arguments
* `name`: a sting with the name
* `myviewer`: the viewer to apply this to. By default the active viewer is used.
* `element`:  the element for which to set the unit (count starts with 0)

#see also
`set_axis_scales_and_units`, `set_value_unit`
"""
function set_value_name(name::String="a.u.", myviewer=nothing; element::Int=0)
    myviewer=get_viewer(myviewer)
    jcall(myviewer, "NameElement", Nothing, (jint, JString), element, name);
    update_panels(myviewer)
    repaint(myviewer)
end

"""
    set_fontsize(fontsize::Int=12, myviewer=nothing)
sets the fontsize for the text display in the viewer.

# Arguments
* `fontsize`: size of the font in pixels (default is 12px)
* `myviewer`: the viewer to apply this to. By default the active viewer is used.
"""
function set_fontsize(fontsize::Int=12, myviewer=nothing)
    myviewer=get_viewer(myviewer)
    jcall(myviewer, "setFontSize", Nothing, (jint,), fontsize);
end

#= function init_layout(myviewer=nothing; element::Int=0)
    myviewer=get_viewer(myviewer)
    jcall(myviewer, "initLayout", Nothing, (jint,), element);
    update_panels(myviewer)
    repaint(myviewer)
end
 =#
function invalidate(myviewer=nothing)
    myviewer=get_viewer(myviewer)
    jcall(myviewer, "invalidate", Nothing, ());
end

"""
    set_min_max_thresh(Min::Float64, Max::Float64, myviewer=nothing; element::Int=0)
sets the minimum and maximum display ranges for a particular element in the viewer

# Arguments
* `min`: the minimum of the display range of this element
* `max`: the maximum of the display range of this element
* `myviewer`: the viewer to apply this to. By default the active viewer is used.
* `element`:  the element for which to set the unit (count starts with 0)

#see also
`set_axis_scales_and_units`
"""
function set_min_max_thresh(Min::Number=0.0, Max::Number=1.0, myviewer=nothing; element=0)
    myviewer=get_viewer(myviewer)
    jcall(myviewer, "setMinMaxThresh", Nothing, (jint, jdouble, jdouble), element, Min, Max);
    update_panels(myviewer);
    repaint(myviewer);
end

"""
    get_num_time(myviewer=nothing)
gets the number of currently existing time points in the viewer

# Arguments
* `myviewer`: The viewer to apply this to. By default the active viewer is used.
"""
function get_num_times(myviewer=nothing)
    myviewer=get_viewer(myviewer)
    num_elem=jcall(myviewer, "getNumTime", jint, ());
end

"""
    export_marker_lists(myviewer=nothing)
gets all the marker lists stored in the viewer as an array of double arrays.

# Arguments
* `myviewer`: the viewer to apply this to. By default the active viewer is used

#Returns
* `markers`: an array of arrays of double. They are interpreted as follows:
    `length(markers)`: overall number of markers
    `markers[1]`: information on the first marker in the following order
* `1:2`     ListNr, MarkerNr, 
* `3:7`     PosX,Y,Z,E,T (all raw subpixel position in pixel coordinates)
* `8:9`     Integral (no BG sub), Max (no BG sub),
* `10:16`   RealPosX,Y,Z,E,T,Integral(no BG sub),Max(no BG sub)  (all as above but this time considering the axes units and scales)
* `17:21`   TagInteger, Parent1, Parent2, Child1, Child2
* `22`      ListColor  (coded)
"""
function export_marker_lists(myviewer=nothing)
    myviewer=get_viewer(myviewer)
    jdoubleArrArr = Vector{Vector{jdouble}}
    return jcall(myviewer, "ExportMarkerLists", jdoubleArrArr, ());
end 

"""
    export_markers_string(myviewer=nothing)
    gets all the marker lists stored in the viewer as a string in human readable form.

# Arguments
* `myviewer`: the viewer to apply this to. By default the active viewer is used

# Returns
a string with the first column indicating the column labels (separated by tab)
followed by rows, each representing a single marker with entries separated by tabs in the following order:
* `1:2`     ListNr, MarkerNr, 
* `3:7`     PosX,Y,Z,E,T (all raw subpixel position in pixel coordinates)
* `8:9`     Integral (no BG sub), Max (no BG sub),
* `10:16`   RealPosX,Y,Z,E,T,Integral(no BG sub),Max(no BG sub)  (all as above but this time considering the axes units and scales)
* `17:21`   TagInteger, Parent1, Parent2, Child1, Child2
* `22`      ListColor  (coded)
"""
function export_markers_string(myviewer=nothing)
    myviewer=get_viewer(myviewer)
    jdoubleArrArr = Vector{Vector{jdouble}}
    return jcall(myviewer, "ExportMarkers", JString, ());
end 

"""
    import_marker_lists(marker_list, myviewer=nothing)
    imports marker lists to be stored and displayed in the viewer.

# Arguments
* `myviewer`: the viewer to apply this to. By default the active viewer is used

# Returns
* `markers`: an array of arrays of double. Please see `export_marker_lists` for a description of the meaning

# See also
export_marker_lists(): The data exported in this way can be read in again by the import_marker_lists routine
"""
function import_marker_lists(marker_lists::Vector{Vector{T}}, myviewer=nothing) where {T}
    myviewer=get_viewer(myviewer)
    if T != Float32
        marker_lists = [convert.(Float32,marker_lists[n]) for n in 1:length(marker_lists)]
    end
    jfloatArrArr = Vector{JavaObject{Vector{jfloat}}}
    converted = JavaCall.convert_arg.(Vector{jfloat}, marker_lists)
    GC.@preserve converted begin
        jcall(myviewer, "ImportMarkerLists", Nothing, (jfloatArrArr,), [c[2] for c in converted]);
    end
    update_panels(myviewer)
    return
end

"""
    delete_all_marker_lists(myviewer=nothing)
deletes all the marker lists, which are stored in the viewer

# Arguments
* `myviewer`: the viewer to apply this to. By default the active viewer is used

# See also:
`export_marker_lists()`, `import_marker_lists()`
"""
function delete_all_marker_lists(myviewer=nothing)
    myviewer=get_viewer(myviewer)
    jcall(myviewer, "DeleteAllMarkerLists", Nothing, ());
    update_panels(myviewer)
    return
end


"""
    to_front(myviewer=nothing)
moves the viewer on top of other windows

# Arguments
* `myviewer`: the viewer to apply this to. By default the active viewer is used
"""
function to_front(myviewer=nothing)
    myviewer=get_viewer(myviewer)
    jcall(myviewer, "toFront", Nothing, ());
end

"""
    hide(myviewer=nothing)
hides the viewer. It can be shown again by calling "to_front"

# Arguments
* `myviewer`: the viewer to apply this to. By default the active viewer is used
"""
function hide_viewer(myviewer=nothing)
    myviewer=get_viewer(myviewer)
    jcall(myviewer, "hide", Nothing, ());
end

function update_panels(myviewer=nothing)
    myviewer=get_viewer(myviewer)
    myviewer=jcall(myviewer, "UpdatePanels", Nothing, ());
end

function repaint(myviewer=nothing)
    myviewer=get_viewer(myviewer)
    myviewer=jcall(myviewer, "repaint", Nothing, ());
end

function process_key_main_window(key::Char, myviewer=nothing)
    myviewer=get_viewer(myviewer)
    myviewer=jcall(myviewer, "ProcessKeyMainWindow", Nothing, (jchar,), key);
    # ProcessKeyMainWindow = javabridge.make_method("ProcessKeyMainWindow","(C)V")
end

"""
    process_key_element_window(key::Char, myviewer=nothing)
Processes a single key in the element window (bottom right panel of "view5d").
For a discription of keys look at the context menu in the viewer. 
More information at https://nanoimaging.de/View5D

# Arguments
* `key`: single key to process inthe element window
* `myviewer`: the viewer to apply this to. By default the active viewer is used
"""
function process_key_element_window(key::Char, myviewer=nothing)
    myviewer=get_viewer(myviewer)
    myviewer=jcall(myviewer, "ProcessKeyElementWindow", Nothing, (jchar,), key);
    # ProcessKeyElementWindow = javabridge.make_method("ProcessKeyElementWindow","(C)V")
end


"""
    process_keys(KeyList::String, myviewer=nothing; mode="main")
Sends key strokes to the viewer. This allows an easy remote-control of the viewer since almost all of its features can be controlled by key-strokes.
Note that panel-specific keys (e.g."q": switching to plot-diplay) are currently not supported.
For a discription of keys look at the context menu in the viewer. 
More information at https://nanoimaging.de/View5D

# Arguments
* `KeyList`: list of keystrokes (as a String) to successively be processed by the viewer. An update is automatically called afterwards.
* `myviewer`: the viewer to which the keys are send.
* `mode`: determines to which panel the keys are sent to. Currently supported: "main" (default) or "element"

# See also
* `process_key_main_window()`: processes a single key in the main window
* `process_key_element_window()`: processes a single key in the element window
"""
function process_keys(KeyList::String, myviewer=nothing; mode="main")
    for k in KeyList
        if mode=="main"
            process_key_main_window(k, myviewer)
        elseif mode=="element"
            process_key_element_window(k, myviewer)
        else
            throw(ArgumentError("unsupported mode $mode. Use `main` or `element`"))
        end
        update_panels(myviewer)
        repaint(myviewer)
    end
    return
end

# myArray= rand(64,64,3,1,1)  # this is the 5D-Array to display
"""
    function to_jtype(something)
converts an array to a jtype array
"""
function to_jtype(anArray)
    ArrayElement = anArray[1]
    if is_complex(anArray)
        jtype=jfloat
        # anArray = permutedims(expanddims(anArray,5),(2,1,3,4,5)) # expanddims(anArray,5) # 
        anArray = expanddims(anArray,5) # 
        #=
        mysize = size(anArray)
        fsize = prod(mysize)
        newsize = Base.setindex(mysize,mysize[5]*2,5)
        myJArr = Array{jtype}(undef, newsize)
        myJArr[1:fsize] .= real.(anArray[:]);  # copies all the real data
        myJArr[fsize+1:2*fsize] .= imag.(anArray[:]);  # copies all the imaginary data
        =#
        mysize = size(anArray)
        fsize = prod(mysize)
        newsize = Base.setindex(mysize,mysize[1]*2,1)
        myJArr = Array{jtype}(undef, newsize)
        #myJArr[:] .= reinterpret(jfloat,anArray[:]),
        myJArr[1:2:2*fsize] .= real.(anArray[:]);  # copies all the real data
        myJArr[2:2:2*fsize] .= imag.(anArray[:]);  # copies all the imaginary data
        return (myJArr, ComplexF32)
    end
    if isa(ArrayElement, RGB)
        anArray = rawview(channelview(anArray))
        anArray = collect(permutedims(expanddims(anArray,5),(3,2,4,1,5)))
        #anArray = collect(permutedims(expanddims(anArray,5),(2,3,4,1,5)))
        # @show size(anArray)
    elseif isa(ArrayElement, Gray)
        anArray = rawview(channelview(permutedims(expanddims(anArray,5),(2,1,3,4,5))))        
        # anArray = expanddims(rawview(channelview(anArray)),5)
    end
    ArrayElement = anArray[1]
    if isa(ArrayElement, Float32)
        jtype=jfloat
    elseif isa(ArrayElement, Float64)
        jtype=jdouble
    elseif isa(ArrayElement, UInt8)
        jtype=jbyte  # fake it...
        anArray = reinterpret(Int8,anArray)
    elseif isa(ArrayElement, Int8)
        jtype=jbyte
    elseif isa(ArrayElement, UInt16)
        jtype=jchar
    elseif isa(ArrayElement, Int16)
        jtype=jshort
    elseif isa(ArrayElement, UInt32)
        jtype=jlong
    elseif isa(ArrayElement, Int32)
        jtype=jlong
    elseif isa(ArrayElement, Int)
        jtype=jint
    end
    # mysize = prod(size(anArray))
    anArray = expanddims(anArray,5) # permutedims(expanddims(anArray,5),(2,1,3,4,5))  # 
    myJArr=Array{jtype}(undef, size(anArray))
    myJArr[:] .= anArray[:]
    #@show jtype
    #@show size(myJArr)
    return (myJArr,jtype)
end

viewers = Dict() # Ref[Dict]

function get_active_viewer()
    if haskey(viewers,"active")
        myviewer=viewers["active"]    
    else
        myviewer=nothing
    end
end

function set_active_viewer(myviewer)
    if haskey(viewers,"active")
        if haskey(viewers,"history")
            push!(viewers["history"], viewers["active"]) 
        else
            viewers["history"]= [viewers["active"] ]
        end
    end
    viewers["active"] = myviewer
end

function get_viewer(viewer=nothing)
    if isnothing(viewer)
        return get_active_viewer()
    else
        return viewer
    end
end

function start_viewer(viewer, myJArr, jtype="jfloat", mode="new", isCpx=false; 
         element=0, mytime=0, name=nothing)
    jArr = Vector{jtype}
    #@show size(myJArr)
    sizeX,sizeY,sizeZ,sizeE,sizeT = size(myJArr)
    addCpx = ""
    if isCpx
        sizeX = Int(sizeX/2)
        addCpx = "C"
    end

    V = @jimport view5d.View5D
    if isnothing(viewer)
        viewer = get_active_viewer();
        if isnothing(viewer)
            viewer=V
        end
    end

    if mode == "new"
        command = string("Start5DViewer", addCpx)
        myviewer=jcall(V, command, V, (jArr, jint, jint, jint, jint, jint),
                        myJArr[:], sizeX, sizeY, sizeZ, sizeE, sizeT);
        if !isnothing(name)
            for E in 0:get_num_elements(myviewer)-1
                set_element_name(E, name, myviewer)
            end
        end            
    elseif mode == "replace"
        command = string("ReplaceData", addCpx)
        #@show viewer 
        jcall(viewer, command, Nothing, (jint, jint, jArr), element, mytime, myJArr[:]);
        myviewer = viewer
    elseif mode == "add_element"
        command = string("AddElement", addCpx)
        size3d = sizeX*sizeY*sizeZ
        for e in 0:sizeE-1
            myviewer=jcall(viewer, command, V, (jArr, jint, jint, jint, jint, jint),
                            myJArr[e*size3d+1:end],sizeX, sizeY, sizeZ, sizeE, sizeT); 
            set_element(-1) # go to the last element
            process_keys("t",myviewer)   
            if !isnothing(name)
                E = get_num_elements()-1
                set_element_name(E, name, myviewer)
            end
        end
    elseif mode == "add_time"
        command = string("AddTime", addCpx)
        size4d = sizeX*sizeY*sizeZ*sizeE
        for t in 0:sizeT-1
            myviewer=jcall(viewer, command, V, (jArr, jint, jint, jint, jint, jint),
                            myJArr[t*size4d+1:end],sizeX, sizeY, sizeZ, sizeE, sizeT);
            set_time(-1) # go to the last element
            for e in 0: get_num_elements()-1 # just to normalize colors and set names
                set_element(e) # go to the this element
                process_keys("t",myviewer)
                if !isnothing(name)
                    set_element_name(e, name, myviewer)
                end
            end
        end
    else
        throw(ArgumentError("unknown mode $mode, choose new, replace, add_element or add_time"))
    end
    return myviewer
end

function add_phase(data, start_element=2, viewer=nothing; name=nothing)
    ne = start_element
    sz=expand_size(size(data),5)
    set_time(-1) # go to the last slice
    for E in 0:sz[4]-1
        phases = 180 .*(angle.(data).+pi)./pi  # in degrees
        # data.unit.append("deg")  # dirty trick
        view5d(phases, viewer; gamma=1.0, mode="add_element", element=ne+E+1, name=name)
        set_value_name(name*"_phase", viewer;element=ne+E)
        set_value_unit("deg", viewer;element=ne+E)
        #@show ne+E
        set_min_max_thresh(0.0, 360.0, viewer;element=ne+E) # to set the color to the correct values
        #update_panels()
        #process_keys("eE") # to normalize this element and force an update also for the gray value image
        #to_front()    

        # process_keys("E", viewer) # advance to next element to the just added phase-only channel
        set_element(-1, viewer)
        process_keys("cccccccccccc", viewer) # toggle color mode 12x to reach the cyclic colormap
        process_keys("56", viewer) # for some reason this avoids dark pixels in the cyclic color display.
        process_keys("vVe", viewer) # Toggle from additive into multiplicative display
    end
    if sz[4]==1
        process_keys("C", viewer) # Back to Multicolor mode
    end
end


function expand_dims(x, N)
    return reshape(x, (size(x)..., ntuple(x -> 1, (N - ndims(x)))...))
end

function expand_size(sz::NTuple, N)
    return (sz..., ntuple(x -> 1, (N - length(sz)))...)
end

"""
    view5d(data :: AbstractArray, viewer=nothing; 
         gamma=nothing, mode="new", element=0, time=0, 
         show_phase=false, keep_zero=false, name=nothing, title=nothing)

Visualizes images and arrays via a Java-based five-dimensional viewer "View5D".
The viewer is interactive and support a wide range of user actions. 
For details see https://nanoimaging.de/View5D

# Arguments
* `data`: the array data to display. A large range of datatypes (including Complex32 and UInt16) is supported.
* `viewer`: of interest only for modes "replace" and "add_element". This viewer instance (as returned by previous calls) is used for display.
        Note that this module keeps track of previously invoked viewers. By default the "viewers["active"]" is used.
* `gamma`: The gamma settings to display this data with. By default the setting is 1.0 for real-valued data and 0.3 for complex valued data.
* `mode`: allows the user to switch between display modes by either 
    `mode="new"` (default): invoking a new View5D.view5d instance to display `data` in
    `mode="replace"`: replacing a single element and time position by `data`. Useful to observe iterative changes.
    `mode="add_element"`, `mode="add_time"`: adds a single (!) element (or timepoint) to the viewer. This can be useful for keeping track of a series of iterative images.
    Note that the modes "replace", "add_element" adn "add_time" only work with a viewer that was previously created via "new".
    Via the "viewer" argument, a specific viewer can be selected. By default the last previously created one is active.
    Note also that it is the user's responsibility to NOT change the size and data-type of the data to display in the modes "replace" and "add_element".
* `element`, `time`: used for mode "replace" to specify which element and and time position needs to be replaced. 
* `show_phase`: determines whether for complex-valued data an extra phase channel is added in multiplicative mode displaying the phase as a value colormap
* `keep_zero`: if true, the brightness display is initialized with a minimum of zero. See also: `set_min_max_thresh()`.
* `name`: if not nothing, sets the name of the added data. The can be useful debug information.
* `title`: if not nothing, sets the initial title of the display window.

# Returns
An instance (JavaCall.JavaObject) or the viewer, which can be used for further manipulation.

# See also
* `set_gamma()`: changes the gamma value to display the data (useful for enhancing low signals)
* `process_keys()`: allows an easy remote-control of the viewer since almost all of its features can be controlled by key-strokes.

# Example
```jldoctest
julia> using View5D
julia> view5d(rand(6,5,4,3,2)) # a viewer with 5D data should popp up
julia> using TestImages
julia> img1 = transpose(Float32.(testimage("resolution_test_512.tif")));
julia> img2 = testimage("mandrill");
julia> img3 = testimage("simple_3d_ball.tif"); # A 3D dataset
julia> v1 = view5d(img1);
julia> v2 = view5d(img2);
julia> v3 = view5d(img3);
julia> using IndexFunArrays
julia> view5d(exp_ikx((100,100),shift_by=(2.3,5.77)).+0, show_phase=true)  # shows a complex-valued phase ramp with cyclic colormap
```
"""
function view5d(data :: AbstractArray, viewer=nothing; gamma=nothing, mode="new", element=0, time=0, show_phase=false, keep_zero=false, name=nothing, title=nothing)
    if ! JavaCall.isloaded()        
        # Uses classpath set in __init__
        JavaCall.init()
        @info "Initializing JavaCall with classpath" JavaCall.getClassPath()
    end
    #V = @JavaCall.jimport view5d.View5D

    myJArr, myDataType=to_jtype(collect(data))
    # myJArr=Array{myDataType}(undef, mysize)
    #myJArr[:].=myArray[:]
    # @show size(myJArr)
    # listmethods(V,"Start5DViewer")
    if myDataType <: Complex
        jArr = Vector{jfloat}
        myviewer = start_viewer(viewer, myJArr,jfloat, mode, true, name=name, element=element, mytime=time)
        set_min_max_thresh(0.0, maximum(abs.(myJArr)), myviewer, element = get_num_elements(myviewer)-1)
        if isnothing(gamma)
            gamma=0.3
        end
    else
        myviewer = start_viewer(viewer, myJArr,myDataType, mode, name=name, element=element, mytime=time)
    end
    set_active_viewer(myviewer)
    # process_keys("Ti12", myviewer)   # to initialize the zoom and trigger the display update
    if !isnothing(gamma)
        set_gamma(gamma,myviewer, element=get_num_elements()-1)
    end
    if keep_zero
        set_min_max_thresh(0.0,maximum(abs.(data)),myviewer, element=get_num_elements()-1)
    end
    if !isnothing(title)
        set_title(title)
    end
    if show_phase && myDataType <: Complex
        if mode=="add_time"
            add_phase(data, get_num_elements(), myviewer, name=name)
        else
            add_phase(data, size(data,4), myviewer, name=name)
        end
    end
    update_panels(myviewer)
    process_keys("eE") # to normalize this element and force an update also for the gray value image
    to_front(myviewer)
    return myviewer
end

"""
    vv(data :: AbstractArray, viewer=nothing; 
         gamma=nothing, mode="new", element=0, time=0, 
         show_phase=true, keep_zero=false, title=nothing)

Visualizes images and arrays via a Java-based five-dimensional viewer "View5D".
The viewer is interactive and support a wide range of user actions. 
For details see https://nanoimaging.de/View5D
This is just a shorthand for the function `view5d`. See `view5d` for arguments description.
See documentation of `view5d` for explanation of the parameters.
"""
function vv(data :: AbstractArray, viewer=nothing; gamma=nothing, mode="new", element=0, time=0, show_phase=false, keep_zero=false, name=nothing, title=nothing)
    view5d(data, viewer; gamma=gamma, mode=mode, element=element, time=time, show_phase=show_phase, keep_zero=keep_zero, name=name, title=title)
end



function display_array(arr::AbstractArray{N,T}, name, disp=vv) where {N,T}
    disp(arr,name=name)
    return "in view5d"
end
function display_array(ex, name, disp=vv) where {N,T}
    repr(begin local value = ex end)
end

using Base
macro vv(exs...)
    blk = Expr(:block)
    for ex in exs
        varname = sprint(Base.show_unquoted, ex)
        name = :(println($(esc(varname))*" = ",
        begin local value=display_array($(esc(ex)),$(esc(varname)),vv) end))
        push!(blk.args, name)
    end
    isempty(exs) || # push!(blk.args, :value)
    return blk
end
macro vep(exs...)
    blk = Expr(:block)
    for ex in exs
        varname = sprint(Base.show_unquoted, ex)
        name = :(println($(esc(varname))*" = ",
        begin local value=display_array($(esc(ex)),$(esc(varname)),vep) end))
        push!(blk.args, name)
    end
    isempty(exs) || # push!(blk.args, :value)
    return blk
end

macro vp(exs...)
    blk = Expr(:block)
    for ex in exs
        varname = sprint(Base.show_unquoted, ex)
        name = :(println($(esc(varname))*" = ",
        begin local value=display_array($(esc(ex)),$(esc(varname)),vp) end))
        push!(blk.args, name)
    end
    isempty(exs) || # push!(blk.args, :value)
    return blk
end
macro ve(exs...)
    blk = Expr(:block)
    for ex in exs
        varname = sprint(Base.show_unquoted, ex)
        name = :(println($(esc(varname))*" = ",
        begin local value=display_array($(esc(ex)),$(esc(varname)),ve) end))
        push!(blk.args, name)
    end
    isempty(exs) || # push!(blk.args, :value)
    return blk
end
macro vt(exs...)
    blk = Expr(:block)
    for ex in exs
        varname = sprint(Base.show_unquoted, ex)
        name = :(println($(esc(varname))*" = ",
        begin local value=display_array($(esc(ex)),$(esc(varname)),vt) end))
        push!(blk.args, name)
    end
    isempty(exs) || # push!(blk.args, :value)
    return blk
end

"""
    vp(data :: AbstractArray, viewer=nothing; 
         gamma=nothing, mode="new", element=0, time=0, 
         show_phase=true, keep_zero=false, title=nothing)

Visualizes images and arrays via a Java-based five-dimensional viewer "View5D".
The viewer is interactive and support a wide range of user actions. 
For details see https://nanoimaging.de/View5D
This is just a shorthand (with `show_phase=true`) for the function `view5d`. See `view5d` for arguments description.
See documentation of `view5d` for explanation of the parameters.
"""
function vp(data :: AbstractArray, viewer=nothing; gamma=nothing, mode="new", element=0, time=0, show_phase=true, keep_zero=false, name=nothing, title=nothing)
    view5d(data, viewer; gamma=gamma, mode=mode, element=element, time=time, show_phase=show_phase, keep_zero=keep_zero, name=name, title=title)
end

"""
    ve(data :: AbstractArray, viewer=nothing; 
         gamma=nothing, element=0, time=0, 
         show_phase=true, keep_zero=false, title=nothing, elements_linked=false)

Visualizes images and arrays via a Java-based five-dimensional viewer "View5D".
The viewer is interactive and support a wide range of user actions. 
For details see https://nanoimaging.de/View5D
This is just a shorthand adding an element to an existing viewer (mode=`add_element`) for the function `view5d`. See `view5d` for arguments description.
See documentation of `view5d` for explanation of the parameters.

`elements_linked`: determines wether all elements are linked together (no indidual scaling and same color)
"""
function ve(data :: AbstractArray, viewer=nothing; gamma=nothing, element=0, time=0, show_phase=false, keep_zero=false, name=nothing, title=nothing, elements_linked=false)
    viewer = get_viewer(viewer)
    set_elements_linked(elements_linked, viewer)
    if isnothing(viewer)
        vv(data, viewer; gamma=gamma, mode="new", element=element, time=time, show_phase=show_phase, keep_zero=keep_zero, name=name, title=title)
    else
        vv(data, viewer; gamma=gamma, mode="add_element", element=element, time=time, show_phase=show_phase, keep_zero=keep_zero, name=name, title=title)
    end
end

"""
    vt(data :: AbstractArray, viewer=nothing; 
         gamma=nothing, element=0, time=0, 
         show_phase=true, keep_zero=false, title=nothing, times_linked=false)

Visualizes images and arrays via a Java-based five-dimensional viewer "View5D".
The viewer is interactive and support a wide range of user actions. 
For details see https://nanoimaging.de/View5D
This is just a shorthand adding an new time point to an existing viewer (mode=`add_time`) for the function `view5d`. See `view5d` for arguments description.
See documentation of `view5d` for explanation of the parameters.

`times_linked`: determines wether all time points are linked together (no indidual scaling)
"""
function vt(data :: AbstractArray, viewer=nothing; gamma=nothing, element=0, time=0, show_phase=false, keep_zero=false, name=nothing, title=nothing, times_linked=false)
    viewer = get_viewer(viewer);
    set_times_linked(times_linked, viewer)
    if isnothing(viewer)
        vv(data, viewer; gamma=gamma, mode="new", element=element, time=time, show_phase=show_phase, keep_zero=keep_zero, name=name, title=title)
    else
        vv(data, viewer; gamma=gamma, mode="add_time", element=element, time=time, show_phase=show_phase, keep_zero=keep_zero, name=name, title=title)
    end
end

"""
    vep(data :: AbstractArray, viewer=nothing; 
         gamma=nothing, element=0, time=0, 
         show_phase=true, keep_zero=false, title=nothing)

Visualizes images and arrays via a Java-based five-dimensional viewer "View5D".
The viewer is interactive and support a wide range of user actions. 
For details see https://nanoimaging.de/View5D
This is just a shorthand (with `show_phase=true`) adding an element to an existing viewer (mode=`add_element`) for the function `view5d`. See `view5d` for arguments description.
See documentation of `view5d` for explanation of the parameters.
"""
function vep(data :: AbstractArray, viewer=nothing; gamma=nothing, element=0, time=0, show_phase=true, keep_zero=false, name=nothing, title=nothing)
    ve(data, viewer; gamma=gamma, element=element, time=time, show_phase=show_phase, keep_zero=keep_zero, name=name, title=title)
end

end # module

#=

This is a copy from my Python file to remind me of future extensions of calling this viewer.
TODO: (already in the python version)
- allow the addition of new elements into the viewer
- allow replacement of elements for live-view updates
- support axis names and scalings
- release as a general release

using JavaCall

begin
           JavaCall.init(["-Djava.class.path=$(joinpath(@__DIR__, "jars","View5D.jar"))"])
           V = @jimport view5d.View5D
           jArr = Vector{jfloat}
           myJArr = rand(jfloat, 5,5,5,5,5);
           myViewer = jcall(V, "Start5DViewerF", V, (jArr, jint, jint, jint, jint, jint), myJArr[:], 5, 5, 5, 5, 5);
end
=#

#=
setSize = javabridge.make_method("setSize","(II)V")
setName = javabridge.make_method("setName","(ILjava/lang/String;)V")
NameElement = javabridge.make_method("NameElement","(ILjava/lang/String;)V")
NameWindow = javabridge.make_method("NameWindow","(Ljava/lang/String;)V")
setFontSize = javabridge.make_method("setFontSize","(I)V")
setUnit = javabridge.make_method("setUnit","(ILjava/lang/String;)V")
SetGamma = javabridge.make_method("SetGamma","(ID)V")
setMinMaxThresh = javabridge.make_method("setMinMaxThresh","(IFF)V")
ProcessKeyMainWindow = javabridge.make_method("ProcessKeyMainWindow","(C)V")
ProcessKeyElementWindow = javabridge.make_method("ProcessKeyElementWindow","(C)V")
UpdatePanels = javabridge.make_method("UpdatePanels","()V")
repaint = javabridge.make_method("repaint","()V")
hide = javabridge.make_method("hide","()V")
toFront = javabridge.make_method("toFront","()V")
SetElementsLinked = javabridge.make_method("SetElementsLinked","(Z)V") # Z means Boolean
closeAll = javabridge.make_method("closeAll","()V")
DeleteAllMarkerLists = javabridge.make_method("DeleteAllMarkerLists","()V")
ExportMarkers = javabridge.make_method("ExportMarkers","(I)[[D")
ExportMarkerLists = javabridge.make_method("ExportMarkerLists","()[[D")
ExportMarkersString = javabridge.make_method("ExportMarkers","()Ljava/lang/String;")
ImportMarkers = javabridge.make_method("ImportMarkers","([[F)V")
ImportMarkerLists = javabridge.make_method("ImportMarkerLists","([[F)V")
AddElem = javabridge.make_method("AddElement","([FIIIII)Lview5d/View5D;")
ReplaceDataB = javabridge.make_method("ReplaceDataB","(I,I[B)V")
setMinMaxThresh = javabridge.make_method("setMinMaxThresh","(IDD)V")
SetAxisScalesAndUnits = javabridge.make_method("SetAxisScalesAndUnits","(DDDDDDDDDDDDLjava/lang/String;[Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;)V")
=#
