# functions for determining whether the Roomba's path interects
# with a line segment and struct defining line segments
# maintained by {jmorton2,kmenda}@stanford.edu


MARGIN = 1e-8
"""
finds the real points of intersection between a line and a circle
inputs: 
- `p0::AbstractVector{Float64}` anchor point 
- `uvec::AbstractVector{Float64}` unit vector specifying heading
- `p1::AbstractVector{Float64}` centroid (x,y) of a circle
- `R::Float64` radius of a circle
returns: 
- `R1,R2::Float64` where R1,R2 are lengths of vec to get from p0 to the intersecting
         points. If intersecting points are imaginary, returns `nothing` in their place
"""
function real_intersect_line_circle(p0::AbstractVector{Float64}, 
                                    uvec::AbstractVector{Float64}, 
                                    p1::AbstractVector{Float64}, 
                                    R::Float64)
    # these equations were generated by Mathematica using the following command:
    # Simplify[Solve[x0 + dx0 * R0 == x && 
    #                y0 + dy0 *R0 == y && 
    #                (x - x1)^2 + (y - y1)^2 == R, 
    #                {x, y, R0}]]
    # Where the solutions for R0 are called R1 and R2 here
    x0, y0 = p0
    dx0, dy0 = uvec
    x1, y1 = p1

    radicand = dx0^2 * (dy0^2 * (R - (x0 - x1)^2) + dx0^2 * (R - (y0 - y1)^2) + 2*dx0*dy0*(x0 - x1)*(y0 - y1))
    if radicand < 0 # intersecting points are imaginary
        return nothing, nothing
    else
        R1 = (1/(dx0*(dx0^2 + dy0^2)))*(dx0^2 * (-x0 + x1) + sqrt(radicand) + dx0*dy0*(-y0 + y1))
        R2 = (1/(dx0*(dx0^2 + dy0^2)))*(dx0^2 * (-x0 + x1) - sqrt(radicand) + dx0*dy0*(-y0 + y1))
        return R1, R2
    end
end

"""
finds the intersection between a line and a line segment
inputs: 
- `p0::AbstractVector{Float64}` anchor point 
- `uvec::AbstractVector{Float64}` unit vector specifying heading
- `p1, p2::AbstractVector{Float64}` x,y of the endpoints of the segment
returns: 
- `sol::AbstractVector{Float64}` x,y of intersection or `nothing` if doesn't intersect
"""
function intersect_line_linesegment(p0::AbstractVector{Float64}, uvec::AbstractVector{Float64}, p1::AbstractVector{Float64}, p2::AbstractVector{Float64})
    dx, dy = uvec
    n = [-dy, dx]
    dprod1 = dot(n, p1-p0)
    dprod2 = dot(n, p2-p0)

    if sign(dprod1) != sign(dprod2)
        # there's an intersection

        # these equations were generated by Mathematica using the following command:
        # Simplify[Solve[x0 + dx0 * R0 == x1 + dx1 * R1 && y0 + dy0 *R0 == y1 + dy1 *R1, {R0,R1}]]
        # Where R0 is the length of the segment originating from p0

        x0, y0 = p0
        x1, y1 = p1
        x2, y2 = p2
        dx0, dy0 = uvec
        dx1 = x2 - x1
        dy1 = y2 - y1
        R = (dy1*x0 - dy1*x1 - dx1*y0 + dx1*y1)/(dx1*dy0 - dx0*dy1)
        if R >= 0
            return R
        else
            return nothing
        end
    else
        return nothing
    end
end

# Define LineSegment
mutable struct LineSegment
    p1::Array{Float64, 1} # anchor point of line-segment
    p2::Array{Float64, 1} # anchor point of line-segment
    goal::Bool # used for rendering purposes
    stairs::Bool # used for rendering purposes
end

"""
determines if traveling in heading from p0 intersects the line passing through this segment
inputs: 
- `ls::LineSegment` line segment under test
- `p0::AbstractVector{Float64}` initial point being travelled from
- `heading::AbstractVector{Float64}` heading unit vector
returns: 
- `::Bool` that is true if pointing toward segment
"""
function pointing_toward_segment(ls::LineSegment, p0::AbstractVector{Float64}, heading::AbstractVector{Float64})
    dp12 = ls.p2 - ls.p1
    normalize!(dp12)
    np12 = [-dp12[2], dp12[1]]

    # ensure it points toward p0
    if dot(np12, p0 - ls.p1) < 0
        np12 *= -1.0
    end

    # return true if heading projects in the opposite direction of np12
    dot(np12, heading) < 0.0
end


"""
computes the length of a ray from robot center to segment from p0 pointing in direction heading
inputs: 
- `ls::LineSegment` line segment under test
- `p0::AbstractVector{Float64}` initial point being travelled from
- `heading::AbstractVector{Float64}` heading unit vector
returns: 
- `::Float64` that is the length of the ray
"""
function ray_length(ls::LineSegment, p0::AbstractVector{Float64}, heading::AbstractVector{Float64})
    p1 = ls.p1
    p2 = ls.p2

    ray_length = Inf

    if !(pointing_toward_segment(ls, p0, heading))
        return ray_length
    else
        intr = intersect_line_linesegment(p0, heading, p1, p2)
        if intr != nothing
            return intr
        else
            return Inf
        end
    end
end


"""
computes the furthest step a robot of radius R can take
inputs: 
- `ls::LineSegment` line segment under test
- `p0::AbstractVector{Float64}` initial point being travelled from
- `heading::AbstractVector{Float64}` heading unit vector
- `R::Float64` radius of robot
returns: 
- `furthest_step::Float64` furthest step the robot can take
--
The way this is computed is by seeing if a ray originating from
p0 in direction heading intersects the following object. Consider
the shape made by moving the robot along the length of the segment.
We can construct this shape by placing a circle with radius of
the robot radius R at each end, and connecting their sides by shifting
segment line out to its left and right by R.
If the line from p0 intersects this object, then choosing the closest 
intersection gives the point at which the robot would stop if traveling
along this line.
"""
function furthest_step(ls::LineSegment, p0::AbstractVector{Float64}, heading::AbstractVector{Float64}, R::Float64)
    furthest_step = Inf

    if !(pointing_toward_segment(ls, p0, heading))
        return furthest_step
    end

    # heading along segment
    dp12 = ls.p2 - ls.p1
    normalize!(dp12)
    np12 = [-dp12[2], dp12[1]]

    # project sides out a robot radius
    p1l = ls.p1 - R*np12
    p1r = ls.p1 + R*np12
    p2l = ls.p2 - R*np12
    p2r = ls.p2 + R*np12

    # intesection with p1
    R1,R2 = real_intersect_line_circle(p0, heading, ls.p1, R/2)

    if R1 != nothing
        if R1 > -MARGIN && R1 < furthest_step
            furthest_step = max(R1, 0.0)
        end
        if R2 > -MARGIN && R2 < furthest_step
            furthest_step = max(R2, 0.0)
        end
    end

    # intesection with p2
    R1, R2 = real_intersect_line_circle(p0, heading, ls.p2, R/2)
    if R1 != nothing
        if R1 > -MARGIN && R1 < furthest_step     
            furthest_step = max(R1, 0.0)
        end
        if R2 > -MARGIN && R2 < furthest_step
            furthest_step = max(R2, 0.0)
        end
    end

    # intersection with the segment
    Rl = intersect_line_linesegment(p0, heading, p1l, p2l)
    if Rl != nothing
        if Rl > -MARGIN && Rl < furthest_step
            furthest_step = max(Rl, 0.0)
        end
    end

    Rr = intersect_line_linesegment(p0, heading, p1r, p2r)
    if Rr != nothing
        if Rr > -MARGIN && Rr < furthest_step
            furthest_step = max(Rr, 0.0)
        end
    end

    if Rl != nothing && Rr != nothing
        if Rl > 0 && Rr < 0
            # something wrong
            println("Travelling through a wall!!")
        end
    end

    furthest_step
end

# Transform coordinates in world frame to coordinates used for rendering
function transform_coords(pos::AbstractVector{Float64})
    x, y = pos

    # Specify dimensions of window
    h = 600
    w = 600

    # Perform conversion
    x_trans = (x + 30.0)/50.0*h
    y_trans = -(y - 20.0)/50.0*w

    x_trans, y_trans
end

# Draw line in gtk window based on start and end coordinates
function render(ls::LineSegment, ctx::CairoContext)
    start_x, start_y = transform_coords(ls.p1)
    if ls.goal
        set_source_rgb(ctx, 0, 1, 0)
    elseif ls.stairs
        set_source_rgb(ctx, 1, 0, 0)
    else
        set_source_rgb(ctx, 0, 0, 0)
    end
    move_to(ctx, start_x, start_y)
    end_x, end_y = transform_coords(ls.p2)
    line_to(ctx, end_x, end_y)
    stroke(ctx)
end
