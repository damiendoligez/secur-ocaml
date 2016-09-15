module O = Obj
let first_non_constant_constructor_tag = O.first_non_constant_constructor_tag (* 0 *)
let last_non_constant_constructor_tag = O.last_non_constant_constructor_tag (* 245 *)

type tag =
  | Constructor of int
  | Lazy | Closure | Object | Infix | Forward
  | Abstract | String | Double | Double_array | Custom
  | Unaligned | Out_of_heap | Int

type obj =
  | Int of int
  | Block of tag * O.t array

let tag_view = let open O in function
                            | t when t == lazy_tag         -> Lazy
                            | t when t == closure_tag      -> Closure
                            | t when t == object_tag       -> Object
                            | t when t == infix_tag        -> Infix
                            | t when t == forward_tag      -> Forward
                            | t when t == abstract_tag     -> Abstract
                            | t when t == string_tag       -> String
                            | t when t == double_tag       -> Double
                            | t when t == double_array_tag -> Double_array
                            | t when t == custom_tag       -> Custom
                            | t when t == unaligned_tag    -> Unaligned
                            | t when t == out_of_heap_tag  -> Out_of_heap
                            | t when t >= first_non_constant_constructor_tag
                                     && t <= last_non_constant_constructor_tag -> Constructor t
                            | t when t == int_tag -> Int
                            | t -> raise (Invalid_argument (__MODULE__ ^ ".tag_view: " ^ string_of_int t))

let fields v =
  Array.init (O.size v) (O.field v)

let view v =
  if O.is_int v then Int (O.obj v)
  else Block (tag_view (O.tag v), fields v)


(** [con_id]: return type of function [con_id]
*)
type con_id = bool * int
(** [con_id]: This function discriminates each constructor of
    a variant datatype by returning a distinct pair of
    (bool,int) for each of them.  The boolean is true iff the
    constructor is constant.  The function doesn't
    discriminate the constructors of extensible variants.
    Also, by its very nature, two constructors of different
    types might have the same con id.
*)
let con_id t =
  (* copy the memory block O.repr(t), with components set to 0 *)
  let open O in
  let ot = repr t in
  let b = is_int ot in
  (b, (if b then obj else tag) ot)

let is_con v =
  O.is_int v
  || O.tag v >= first_non_constant_constructor_tag
     && O.tag v <= last_non_constant_constructor_tag

(** The size of a block or [0] for an immediate value.
*)
let gsize = function
  | v when O.is_int v -> 0
  | v -> O.size v

let is_tuple x =
  let t = O.tag x in
  t > O.first_non_constant_constructor_tag
  && t < O.no_scan_tag

(** [x] and [y] must both be block of the same length,
and the binary predicate must hold for all their fields:

{v
forall i . p (x.i, y.i)
v}

*)

let fields_all2 p x y =
  let open O in
  is_tuple x && is_tuple y
  && size x == size y
  && Generic_util_iter.for_all_in 0 (size x - 1)
                     (fun i -> p (field x i) (field y i))

(** Equality on objects. (Same as Pervasive.=)
   {e todo}: use memoisation to deal with cyclic datastructures
   unsafe on custom types
let rec obj_eq x y =
  con_id x = con_id y
  && (O.is_int x
      || fields_all2 obj_eq x y)
*)

(* Given a obj of type (x0,...xn)
  Computes a nested product (x0, (x1, (..., xn) ...))
 *)
let listify x =
  let rec go tail = function
    | i when i < 0 -> tail
    | i -> let c = O.new_block 0 2 in
           begin
             O.set_field c 0 (O.field x i);
             O.set_field c 1 tail;
             go c (i-1);
           end
  in if is_tuple x
  then go (O.repr ()) (O.size x - 1)
  else raise (Invalid_argument (__MODULE__ ^ ".listify: not a tuple"))

(* PARTIAL. polymorpic variants *)
let poly_hash x =
  let open O in
  let v = repr x in
  if is_int v then obj v
  else if size v > 0 then obj (field v 0)
  else raise (Invalid_argument (__MODULE__ ^ ".poly_hash: not a polymorphic variant"))

(* TOTAL. A constructor of an extensible variant type is
  an object with two fields: a string (the name) and an int *)
let is_ext_con x =
  let open O in
  is_block x
  && tag x == object_tag
  && size x == 2
  && tag (field x 0) == string_tag
  && is_int (field x 1)

(* PARTIAL. raise Invalid_argument
   Extract the constructor of an extensible variant,
   from a value which may be a constructor application
   ENSURES is_ext_con x *)
let ext_con x =
  let c = if O.is_block x && O.tag x == 0 && O.size x > 1
          then O.field x 0 else x
  in if is_ext_con c then c
     else raise (Invalid_argument (__MODULE__ ^ ".ext_con"))

(* PARTIAL *)
let ext_con_name x = (O.obj (O.field (ext_con x) 0) : string)

(* PARTIAL *)
let ext_con_id x = (O.obj (O.field (ext_con x) 1) : int)
let ext_con_set_id x id = O.set_field (ext_con x) 1 (O.repr id)

(* TOTAL. Returns the identifier of a custom block,
    or the empty string if the block isn't a custom one. *)
external custom_identifier : 'a -> string = "caml_custom_identifier"

(* TOTAL. duplicate blocks and returns identity on integers *)
let dup_if_block v = if O.is_int v then v else O.dup v
