# Array info
for (mod, fname) in ((:Base, :size), (:Base, :axes), (:Base, :firstindex), (:Base, :lastindex))
    @eval begin
        @inline ($mod.$fname)(A::AbstractArray, dims::AllDimensions) =
            ($mod.$fname)(A, dimnum(A, dims))
    end
end

# Reducing methods

for (mod, fname) in ((:Base, :sum), (:Base, :prod), (:Base, :maximum), (:Base, :minimum), (:Statistics, :mean))
    _fname = Symbol('_', fname)
    @eval begin
        # Returns a scalar
        @inline ($mod.$fname)(A::AbDimArray) = ($mod.$fname)(data(A))
        # Returns a reduced array
        @inline ($mod.$_fname)(A::AbstractArray, dims::AllDimensions) =
            rebuild(A, ($mod.$_fname)(data(A), dimnum(A, dims)), reducedims(A, dims))
        @inline ($mod.$_fname)(f, A::AbstractArray, dims::AllDimensions) =
            rebuild(A, ($mod.$_fname)(f, data(A), dimnum(A, dims)), reducedims(A, dims))
        @inline ($mod.$_fname)(A::AbDimArray, dims::Union{Int,Base.Dims}) =
            rebuild(A, ($mod.$_fname)(data(A), dims), reducedims(A, dims))
        @inline ($mod.$_fname)(f, A::AbDimArray, dims::Union{Int,Base.Dims}) =
            rebuild(A, ($mod.$_fname)(f, data(A), dims), reducedims(A, dims))
    end
end

for (mod, fname) in ((:Statistics, :std), (:Statistics, :var))
    _fname = Symbol('_', fname)
    @eval begin
        # Returns a scalar
        @inline ($mod.$fname)(A::AbDimArray) = ($mod.$fname)(data(A))
        # Returns a reduced array
        @inline ($mod.$_fname)(A::AbstractArray, corrected::Bool, mean, dims::AllDimensions) =
            rebuild(A, ($mod.$_fname)(A, corrected, mean, dimnum(A, dims)), reducedims(A, dims))
        @inline ($mod.$_fname)(A::AbDimArray, corrected::Bool, mean, dims::Union{Int,Base.Dims}) =
            rebuild(A, ($mod.$_fname)(data(A), corrected, mean, dims), reducedims(A, dims))
    end
end

Statistics.median(A::AbDimArray) = Statistics.median(data(A))
Statistics._median(A::AbstractArray, dims::AllDimensions) =
    rebuild(A, Statistics._median(data(A), dimnum(A, dims)), reducedims(A, dims))
Statistics._median(A::AbDimArray, dims::Union{Int,Base.Dims}) =
    rebuild(A, Statistics._median(data(A), dims), reducedims(A, dims))

Base._mapreduce_dim(f, op, nt::NamedTuple{(),<:Tuple}, A::AbstractArray, dims::AllDimensions) =
    rebuild(A, Base._mapreduce_dim(f, op, nt, data(A), dimnum(A, dims)), reducedims(A, dims))
Base._mapreduce_dim(f, op, nt::NamedTuple{(),<:Tuple}, A::AbDimArray, dims::Union{Int,Base.Dims}) =
    rebuild(A, Base._mapreduce_dim(f, op, nt, data(A), dimnum(A, dims)), reducedims(A, dims))
Base._mapreduce_dim(f, op, nt::NamedTuple{(),<:Tuple}, A::AbDimArray, dims::Colon) =
    Base._mapreduce_dim(f, op, nt, data(A), dims)

# TODO: Unfortunately Base/accumulate.jl kwargs methods all force dims to be Integer.
# accumulate wont work unless that is relaxed, or we copy half of the file here.
# Base._accumulate!(op, B, A, dims::AllDimensions, init::Union{Nothing, Some}) =
    # Base._accumulate!(op, B, A, dimnum(A, dims), init)

Base._extrema_dims(f, A::AbstractArray, dims::AllDimensions) = begin
    dnums = dimnum(A, dims)
    rebuild(A, Base._extrema_dims(f, data(A), dnums), reducedims(A, dnums))
end


# Dimension dropping

Base._dropdims(A::AbstractArray, dim::DimOrDimType) =
    rebuildsliced(A, Base._dropdims(A, dimnum(A, dim)), dims2indices(A, basetypeof(dim)(1)))
Base._dropdims(A::AbstractArray, dims::AbDimTuple) =
    rebuildsliced(A, Base._dropdims(A, dimnum(A, dims)),
                  dims2indices(A, Tuple((basetypeof(d)(1) for d in dims))))


# Function application

@inline Base.map(f, A::AbDimArray) = rebuild(A, map(f, data(A)), dims(A))

Base.mapslices(f, A::AbDimArray; dims=1, kwargs...) = begin
    dimnums = dimnum(A, dims)
    _data = mapslices(f, data(A); dims=dimnums, kwargs...)
    rebuild(A, _data, reducedims(A, DimensionalData.dims(A, dimnums)))
end

# This is copied from base as we can't efficiently wrap this function
# through the kwarg with a rebuild in the generator. Doing it this way
# also makes it faster to use a dim than an integer.
if VERSION > v"1.1-"
    Base.eachslice(A::AbDimArray; dims=1, kwargs...) = begin
        if dims isa Tuple && length(dims) != 1
            throw(ArgumentError("only single dimensions are supported"))
        end
        dim = first(dimnum(A, dims))
        dim <= ndims(A) || throw(DimensionMismatch("A doesn't have $dim dimensions"))
        idx1, idx2 = ntuple(d->(:), dim-1), ntuple(d->(:), ndims(A)-dim)
        return (view(A, idx1..., i, idx2...) for i in axes(A, dim))
    end
end

# Duplicated dims

for fname in (:cor, :cov)
    @eval Statistics.$fname(A::AbDimArray{T,2}; dims=1, kwargs...) where T = begin
        newdata = Statistics.$fname(data(A); dims=dimnum(A, dims), kwargs...)
        I = dims2indices(A, dims, 1)
        newdims, newrefdims = slicedims(A, I)
        rebuild(A, newdata, (newdims[1], newdims[1]), newrefdims)
    end
end

const AA = AbstractArray
const ADA = AbstractDimensionalArray

Base.:*(A::ADA{<:Any,2}, B::AA{<:Any,1}) = rebuild(A, data(A) * B, dims(A, (1,)))
Base.:*(A::ADA{<:Any,1}, B::AA{<:Any,2}) = rebuild(A, data(A) * B, dims(A, (1, 1)))
Base.:*(A::ADA{<:Any,2}, B::AA{<:Any,2}) = rebuild(A, data(A) * B, dims(A, (1, 1)))
Base.:*(A::AA{<:Any,1}, B::ADA{<:Any,2}) = rebuild(B, A * data(B), dims(B, (2, 2)))
Base.:*(A::AA{<:Any,2}, B::ADA{<:Any,1}) = rebuild(B, A * data(B), (EmptyDim(),))
Base.:*(A::AA{<:Any,2}, B::ADA{<:Any,2}) = rebuild(B, A * data(B), dims(B, (2, 2)))

Base.:*(A::ADA{<:Any,1}, B::ADA{<:Any,2}) = begin
    _checkmatch(dims(A, 1), dims(B, 2))
    rebuild(A, data(A) * data(B), dims(A, (1, 1)))
end
Base.:*(A::AbDimArray{<:Any,2}, B::AbDimArray{<:Any,1}) = begin
    _checkmatch(dims(A, 2), dims(B, 1))
    rebuild(A, data(A) * data(B), dims(A, (1,)))
end
Base.:*(A::ADA{<:Any,2}, B::ADA{<:Any,2}) = begin
    _checkmatch(dims(A), reverse(dims(B)))
    rebuild(A, data(A) * data(B), dims(A, (1, 1)))
end

_checkmatch(a, b) =
    a == b || throw(ArgumentError("Array dims $a and $b do not match"))

# Reverse

@inline Base.reverse(A::AbDimArray{T,N}; dims=1) where {T,N} = begin
    dnum = dimnum(A, dims)
    # Reverse the dimension. TODO: make this type stable
    newdims = reversearray(DimensionalData.dims(A), dnum)
    # Reverse the data
    newdata = reverse(data(A); dims=dnum)
    rebuild(A, newdata, newdims, refdims(A))
end

@inline reversearray(dimstorev::Tuple, dnum) = begin
    dim = dimstorev[end]
    if length(dimstorev) == dnum
        dim = rebuild(dim, val(dim), reversearray(grid(dim)))
    end
    (reversearray(Base.front(dimstorev), dnum)..., dim)
end
@inline reversearray(dims::Tuple{}, i) = ()


# Dimension reordering

for (pkg, fname) in [(:Base, :permutedims), (:Base, :adjoint),
                     (:Base, :transpose), (:LinearAlgebra, :Transpose)]
    @eval begin
        @inline $pkg.$fname(A::AbDimArray{T,2}) where T =
            rebuild(A, $pkg.$fname(data(A)), reverse(dims(A)), refdims(A))
        @inline $pkg.$fname(A::AbDimArray{T,1}) where T =
            rebuild(A, $pkg.$fname(data(A)), (EmptyDim(), dims(A)...))
    end
end

for fname in [:permutedims, :PermutedDimsArray]
    @eval begin
        @inline Base.$fname(A::AbDimArray{T,N}, perm) where {T,N} =
            rebuild(A, $fname(data(A), dimnum(A, perm)), permutedims(dims(A), perm))
    end
end


# Concatenation

Base._cat(catdims::Union{Int,Base.Dims}, As::AbDimArray...) =
    Base._cat(dims(first(As), catdims), As...)
Base._cat(catdims::AllDimensions, As::AbstractArray...) = begin
    A1 = first(As)
    checkdims(As...)
    if all(hasdim(A1, catdims))
        # Concatenate an existing dim
        dnum = dimnum(A1, catdims)
        # cat the catdim, ignore others
        newdims = Tuple(_catifcatdim(catdims, ds) for ds in zip(map(dims, As)...))
    else
        # Concatenate a new dim
        add_dims = if (catdims isa Tuple)
            Tuple(d for d in catdims if !hasdim(A1, d))
        else
            (catdims,)
        end
        dnum = ndims(A1) + length(add_dims)
        newdims = (dims(A1)..., add_dims...)
    end
    newA = Base._cat(dnum, map(data, As)...)
    rebuild(A1; data=newA, dims=formatdims(newA, newdims))
end

_catifcatdim(catdims::Tuple, ds) =
    any(map(cd -> basetypeof(cd) <: basetypeof(ds[1]), catdims)) ? vcat(ds...) : ds[1]
_catifcatdim(catdim, ds) = basetypeof(catdim) <: basetypeof(ds[1]) ? vcat(ds...) : ds[1]

Base.vcat(dims::AbDim...) =
    rebuild(dims[1], vcat(map(val, dims)...), vcat(map(grid, dims)...))

Base.vcat(grids::Grid...) = first(grids)
Base.vcat(grids::RegularGrid...) = begin
    _step = step(grids[1])
    map(grids) do grid
        step(grid) == _step || error("Step sizes $(step(grid)) and $_step do not match ")
    end
    first(grids)
end
Base.vcat(grids::BoundedGrid...) =
    rebuild(grids[1]; bounds=(bounds(grids[1])[1], bounds(grids[end])[end]))

checkdims(A::AbstractArray...) = checkdims(map(dims, A)...)
checkdims(dims::AbDimTuple...) = map(d -> checkdims(dims[1], d), dims)
checkdims(d1::AbDimTuple, d2::AbDimTuple) = map(checkdims, d1, d2)
checkdims(d1::AbDim, d2::AbDim) =
    basetypeof(d2) <: basetypeof(d1) || error("Dims differ: $(bastypeof(d1)), $(basetypeof(d2))")


# Index breaking

# TODO: change the index and traits of the reduced dimension
# and return a DimensionalArray.
Base.unique(A::AbDimArray{<:Any,1}) = unique(data(A))
Base.unique(A::AbDimArray; dims::DimOrDimType) =
    unique(data(A); dims=dimnum(A, dims))


# TODO cov, cor mapslices, eachslice, reverse, sort and sort! need _methods without kwargs in base so
# we can dispatch on dims. Instead we dispatch on array type for now, which means
# these aren't usefull unless you inherit from AbDimArray.
