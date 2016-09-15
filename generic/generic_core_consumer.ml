(* generic consumers have a type "'a . 'a ty -> 'a -> 'b"
 *)

open Generic_core
open Generic_util_app

type 'b ty_fun =
  { f : 'a . 'a Ty.ty -> 'a -> 'b }

type 'b closure =
  { f : 'a . 'a Ty.ty -> 'a -> 'b
  ; ext : 'a . 'a Ty.ty -> 'b ty_fun -> unit
  }

let create name =
  let closure = Extensible.create name
  in { f = (fun t x -> get_exponential (closure.f t) x)
     ; ext = (fun t f -> closure.ext t
               { f = fun t -> Exponential (f.f t)})
     }
