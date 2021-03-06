
abstract type AbstractDimensionalArray{T,N,D<:Tuple,A} <: AbstractArray{T,N} end

const AbDimArray = AbstractDimensionalArray

const StandardIndices = Union{AbstractArray,Colon,Integer}

# Interface methods ############################################################

dims(A::AbDimArray) = A.dims
@inline rebuild(x, data, dims=dims(x)) = rebuild(x, data, dims, refdims(x))


# Array interface methods ######################################################

Base.size(A::AbDimArray) = size(data(A))
Base.iterate(A::AbDimArray, args...) = iterate(data(A), args...)

Base.@propagate_inbounds Base.getindex(A::AbDimArray{<:Any, N}, I::Vararg{<:Integer, N}) where N =
    getindex(data(A), I...)
Base.@propagate_inbounds Base.getindex(A::AbDimArray, I::Vararg{<:StandardIndices}) =
    rebuildsliced(A, getindex(data(A), I...), I)

# Linear indexing
Base.@propagate_inbounds Base.getindex(A::AbDimArray{<:Any, N} where N, I::StandardIndices) =
    getindex(data(A), I)
# Exempt 1D DimArrays
Base.@propagate_inbounds Base.getindex(A::AbDimArray{<:Any, 1}, I::Union{Colon, AbstractArray}) =
    rebuildsliced(A, getindex(data(A), I), (I,))

Base.@propagate_inbounds Base.view(A::AbDimArray, I::Vararg{<:StandardIndices}) =
    rebuildsliced(A, view(data(A), I...), I)
Base.@propagate_inbounds Base.view(A::AbDimArray{<:Any, 1}, I::StandardIndices) =
    rebuildsliced(A, view(data(A), I), (I,))
Base.@propagate_inbounds Base.view(A::AbDimArray{<:Any, N} where N, I::StandardIndices) =
    view(data(A), I)

Base.@propagate_inbounds Base.setindex!(A::AbDimArray, x, I::Vararg{StandardIndices}) =
    setindex!(data(A), x, I...)

Base.copy(A::AbDimArray) = rebuild(A, copy(data(A)))
Base.copy!(dst::AbDimArray, src::AbDimArray) = copy!(data(dst), data(src))
Base.copy!(dst::AbDimArray, src::AbstractArray) = copy!(data(dst), src)
Base.copy!(dst::AbstractArray, src::AbDimArray) = copy!(dst, data(src))

# Need to cover a few type signatures to avoid ambiguity with base
# Don't remove these even though they look redundant
Base.similar(A::AbDimArray) = rebuild(A, similar(data(A)))
Base.similar(A::AbDimArray, ::Type{T}) where T = rebuild(A, similar(data(A), T))
Base.similar(A::AbDimArray, ::Type{T}, I::Tuple{Int64,Vararg{Int64}}) where T =
    rebuild(A, similar(data(A), T, I))
Base.similar(A::AbDimArray, ::Type{T}, I::Tuple{Union{Integer,AbstractRange},Vararg{Union{Integer,AbstractRange},N}}) where {T,N} =
    rebuildsliced(A, similar(data(A), T, I...), I)
Base.similar(A::AbDimArray, ::Type{T}, I::Vararg{<:Integer}) where T =
    rebuildsliced(A, similar(data(A), T, I...), I)
Base.similar(bc::Broadcast.Broadcasted{Broadcast.ArrayStyle{AbDimArray}}, ::Type{ElType}) where ElType = begin
    A = find_dimensional(bc)
    # TODO How do we know what the new dims are?
    rebuildsliced(A, similar(Array{ElType}, axes(bc)), axes(bc))
end


@inline find_dimensional(bc::Base.Broadcast.Broadcasted) = find_dimensional(bc.args)
@inline find_dimensional(ext::Base.Broadcast.Extruded) = find_dimensional(ext.x)
@inline find_dimensional(args::Tuple{}) = error("dimensional array not found")
@inline find_dimensional(args::Tuple) = find_dimensional(find_dimensional(args[1]), tail(args))
@inline find_dimensional(x) = x
@inline find_dimensional(A::AbDimArray, rest) = A
@inline find_dimensional(::Any, rest) = find_dimensional(rest)


# Concrete implementation ######################################################

"""
    DimensionalArray(A::AbstractArray, dims::Tuple, refdims::Tuple)

A basic DimensionalArray type.

Maintains and updates its dimensions through transformations
"""
struct DimensionalArray{T,N,D<:Tuple,R<:Tuple,A<:AbstractArray{T,N}} <: AbstractDimensionalArray{T,N,D,A}
    data::A
    dims::D
    refdims::R
end
"""
    DimensionalArray(A::AbstractArray, dims::Tuple; refdims=())
Constructor with optional `refdims` keyword.

Example:

```
using Dates, DimensionalData
timespan = DateTime(2001):Month(1):DateTime(2001,12)
A = DimensionalArray(rand(12,10), (Ti(timespan), X(10:10:100)))
A[X<|Near([12, 35]), Ti<|At(DateTime(2001,5))]
A[Near(DateTime(2001, 5, 4)), Between(20, 50)]
```
"""
DimensionalArray(A::AbstractArray, dims; refdims=()) =
    DimensionalArray(A, formatdims(A, dims), refdims)

# Getters
refdims(A::DimensionalArray) = A.refdims
data(A::DimensionalArray) = A.data

# DimensionalArray interface
@inline rebuild(A::DimensionalArray, data, dims, refdims) =
    DimensionalArray(data, dims, refdims)
