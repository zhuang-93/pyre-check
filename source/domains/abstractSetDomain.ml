(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open AbstractDomainCore

module type ELEMENT = sig
  type t [@@deriving show]

  val name : string

  val compare : t -> t -> int
end

module type S = sig
  include AbstractDomainCore.S

  type element

  type _ AbstractDomainCore.part +=
    | Element : element AbstractDomainCore.part | Set : element list AbstractDomainCore.part

  val add : element -> t -> t

  val remove : element -> t -> t

  val singleton : element -> t

  val elements : t -> element list

  val of_list : element list -> t
end

module Make (Element : ELEMENT) = struct
  module Set = Set.Make (Element)

  module rec Base : (BASE with type t := Set.t) = MakeBase (Domain)

  and Domain : (S with type t = Set.t and type element = Set.elt) = struct
    include Set

    type element = Element.t

    type _ part += Self : t part | Element : Element.t part | Set : Element.t list part

    let bottom = Set.empty

    let is_bottom = Set.is_empty

    let join left right =
      if left == right then
        left
      else
        Set.union left right


    let meet left right =
      if left == right then
        left
      else
        Set.inter left right


    let widen ~iteration:_ ~prev ~next = join prev next

    let less_or_equal ~left ~right =
      if left == right || is_bottom left then
        true
      else if is_bottom right then
        false
      else
        Set.subset left right


    let subtract to_remove ~from =
      if to_remove == from || is_bottom from then
        bottom
      else if is_bottom to_remove then
        from
      else
        Set.diff from to_remove


    let show set =
      Set.elements set
      |> ListLabels.map ~f:Element.show
      |> String.concat ", "
      |> Format.sprintf "[%s]"


    let pp formatter set = Format.fprintf formatter "%s" (show set)

    let transform : type a f. a part -> ([ `Transform ], a, f, t, t) operation -> f:f -> t -> t =
     fun part op ~f set ->
      match part, op with
      | Element, Map -> Set.map f set
      | Element, Add -> Set.add f set
      | Element, Filter -> Set.filter f set
      | Set, Map -> f (Set.elements set) |> Set.of_list
      | Set, Add -> Set.elements set |> List.rev_append f |> Set.of_list
      | Set, Filter ->
          if f (Set.elements set) then
            set
          else
            bottom
      | _ -> Base.transform part op ~f set


    let reduce
        : type a f b. a part -> using:([ `Reduce ], a, f, t, b) operation -> f:f -> init:b -> t -> b
      =
     fun part ~using:op ~f ~init set ->
      match part, op with
      | Element, Acc -> Set.fold f set init
      | Element, Exists -> init || Set.exists f set
      | Set, Acc -> f (Set.elements set) init
      | Set, Exists -> init || f (Set.elements set)
      | _ -> Base.reduce part ~using:op ~f ~init set


    let partition
        : type a f b.
          a part ->
          ([ `Partition ], a, f, t, b) operation ->
          f:f ->
          t ->
          (b, t) Core_kernel.Map.Poly.t
      =
     fun part op ~f set ->
      let update element = function
        | None -> Set.singleton element
        | Some set -> Set.add element set
      in
      match part, op with
      | Element, By ->
          let f element result =
            Core_kernel.Map.Poly.update result (f element) ~f:(update element)
          in
          Set.fold f set Core_kernel.Map.Poly.empty
      | Set, By ->
          let key = f (Set.elements set) in
          Core_kernel.Map.Poly.singleton key set
      | Element, ByFilter ->
          let f element result =
            match f element with
            | None -> result
            | Some key -> Core_kernel.Map.Poly.update result key ~f:(update element)
          in
          Set.fold f set Core_kernel.Map.Poly.empty
      | Set, ByFilter -> (
          match f (Set.elements set) with
          | None -> Core_kernel.Map.Poly.empty
          | Some key -> Core_kernel.Map.Poly.singleton key set )
      | _ -> Base.partition part op ~f set


    let introspect (type a) (op : a introspect) : a =
      match op with
      | GetParts f ->
          f#report Self;
          f#report Element;
          f#report Set
      | Structure -> [Format.sprintf "Set(%s)" Element.name]
      | Name part -> (
          match part with
          | Element -> Format.sprintf "Set(%s).Element" Element.name
          | Set -> Format.sprintf "Set(%s).Set" Element.name
          | Self -> Format.sprintf "Set(%s).Self" Element.name
          | _ -> Base.introspect op )


    let create parts =
      let create_part so_far (Part (part, value)) =
        match part with
        | Set -> join so_far (Set.of_list value)
        | Element -> Set.add value so_far
        | _ -> Base.create part value so_far
      in
      ListLabels.fold_left parts ~f:create_part ~init:bottom


    let fold = Base.fold
  end

  let _ = Base.fold (* unused module warning work-around *)

  include Domain
end