(* Copyright (C) 2009,2017,2019 Matthew Fluet.
 * Copyright (C) 1999-2007 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a HPND-style license.
 * See the file MLton-LICENSE for details.
 *)

signature RSSA_TREE_STRUCTS =
   sig
      include BACKEND_ATOMS
   end

signature RSSA_TREE =
   sig
      include RSSA_TREE_STRUCTS

      structure Switch: SWITCH
      sharing Atoms = Switch

      structure Operand:
         sig
            datatype t =
               Cast of t * Type.t
             | Const of Const.t
             | GCState
             | Offset of {base: t,
                          offset: Bytes.t,
                          ty: Type.t}
             | ObjptrTycon of ObjptrTycon.t
             | Runtime of Runtime.GCField.t
             | SequenceOffset of {base: t,
                                  index: t,
                                  offset: Bytes.t,
                                  scale: Scale.t,
                                  ty: Type.t}
             | Var of {ty: Type.t,
                       var: Var.t}
               (* `Address` is used to create temporary internal pointers,
                * to pass to the runtime write barrier. It is okay to take
                * the address ONLY of Offsets and ArrayOffsets. The program
                * should never "hold on to" an internal pointer. *)
             | Address of t

            val bool: bool -> t
            val cast: t * Type.t -> t
            val layout: t -> Layout.t
            val null: t
            val replaceVar: t * (Var.t -> t) -> t
            val ty: t -> Type.t
            val word: WordX.t -> t
            val zero: WordSize.t -> t
         end
      sharing Operand = Switch.Use

      structure Statement:
         sig
            datatype t =
               Bind of {dst: Var.t * Type.t,
                        isMutable: bool,
                        src: Operand.t}
             | Move of {dst: Operand.t,
                        src: Operand.t}
             | Object of {dst: Var.t * Type.t,
                          header: word,
                          size: Bytes.t (* including header *)}
             | PrimApp of {args: Operand.t vector,
                           dst: (Var.t * Type.t) option,
                           prim: Type.t Prim.t}
             | Profile of ProfileExp.t
             | ProfileLabel of ProfileLabel.t
             | SetExnStackLocal
             | SetExnStackSlot
             | SetHandler of Label.t (* label must be of Handler kind. *)
             | SetSlotExnStack

            (* foldDef (s, a, f)
             * If s defines a variable x, then return f (x, a), else return a.
             *)
            val foldDef: t * 'a * (Var.t * Type.t * 'a -> 'a) -> 'a
            (* foreachDef (s, f) = foldDef (s, (), fn (x, ()) => f x) *)
            val foreachDef: t * (Var.t * Type.t -> unit) -> unit
            val foreachDefUse: t * {def: (Var.t * Type.t) -> unit,
                                    use: Var.t -> unit} -> unit
            val foldUse: t * 'a * (Var.t * 'a -> 'a) -> 'a
            val foreachUse: t * (Var.t -> unit) -> unit
            val layout: t -> Layout.t
            val replaceUses: t * (Var.t -> Operand.t) -> t
            val resize: Operand.t * Type.t -> Operand.t * t list
            val toString: t -> string
         end

      structure Transfer:
         sig
            datatype t =
               CCall of {args: Operand.t vector,
                         func: Type.t CFunction.t,
                         (* return is NONE iff the CFunction doesn't return.
                          * Else, return must be SOME l, where l is of kind
                          * CReturn.  The return should be nullary if the C
                          * function returns void.  Else, it should be unary with
                          * a var of the appropriate type to accept the result.
                          *)
                         return: Label.t option}
             | Call of {args: Operand.t vector,
                        func: Func.t,
                        return: Return.t}
             | Goto of {args: Operand.t vector,
                        dst: Label.t}
             (* Raise implicitly raises to the caller.  
              * I.E. the local handler stack must be empty.
              *)
             | Raise of Operand.t vector
             | Return of Operand.t vector
             | Switch of Switch.t

            val bug: unit -> t
            val foreachLabelUse: t * {label: Label.t -> unit,
                                      use: Var.t -> unit} -> unit
            val foreachFunc: t * (Func.t -> unit) -> unit
            val foreachLabel: t * (Label.t -> unit) -> unit
            val foreachUse: t * (Var.t -> unit) -> unit
            val ifBool: Operand.t * {falsee: Label.t, truee: Label.t} -> t
            (* in ifZero, the operand should be of type defaultWord *)
            val ifZero: Operand.t * {falsee: Label.t, truee: Label.t} -> t
            val layout: t -> Layout.t
            val replaceLabels: t * (Label.t -> Label.t) -> t
            val replaceUses: t * (Var.t -> Operand.t) -> t
         end

      structure Kind:
         sig
            datatype t =
               Cont of {handler: Handler.t}
             | CReturn of {func: Type.t CFunction.t}
             | Handler
             | Jump

            datatype frameStyle = None | OffsetsAndSize | SizeOnly
            val frameStyle: t -> frameStyle
         end

      structure Block:
         sig
            datatype t =
               T of {args: (Var.t * Type.t) vector,
                     kind: Kind.t,
                     label: Label.t,
                     statements: Statement.t vector,
                     transfer: Transfer.t}

            val clear: t -> unit
            val foreachDef: t * (Var.t * Type.t -> unit) -> unit
            val foreachUse: t * (Var.t -> unit) -> unit
            val kind: t -> Kind.t
            val label: t -> Label.t
            val layout: t -> Layout.t
         end

      structure Function:
         sig
            type t

            val blocks: t -> Block.t vector
            val clear: t -> unit
            val dest: t -> {args: (Var.t * Type.t) vector,
                            blocks: Block.t vector,
                            name: Func.t,
                            raises: Type.t vector option,
                            returns: Type.t vector option,
                            start: Label.t}
            (* dfs (f, v) visits the blocks in depth-first order, applying v b
             * for block b to yield v', then visiting b's descendents,
             * then applying v' ().
             *)
            val dfs: t * (Block.t -> unit -> unit) -> unit
            val dominatorTree: t -> Block.t Tree.t
            val foreachDef: t * (Var.t * Type.t -> unit) -> unit
            val foreachUse: t * (Var.t -> unit) -> unit
            val layout: t -> Layout.t
            val layoutHeader: t -> Layout.t
            (* Produce a loop forest, with an optional predicate;
             * the start node will be connected when
             * the predicate fails, to maintain connectedness *)
            val loopForest: t * (Block.t * Block.t -> bool) -> Block.t DirectedGraph.LoopForest.t
            val name: t -> Func.t
            val new: {args: (Var.t * Type.t) vector,
                      blocks: Block.t vector,
                      name: Func.t,
                      raises: Type.t vector option,
                      returns: Type.t vector option,
                      start: Label.t} -> t
         end

      structure Program:
         sig
            datatype t =
               T of {functions: Function.t list,
                     handlesSignals: bool,
                     main: Function.t,
                     objectTypes: ObjectType.t vector,
                     profileInfo: {sourceMaps: SourceMaps.t,
                                   getFrameSourceSeqIndex: Label.t -> int option} option}

            val clear: t -> unit
            val checkHandlers: t -> unit
            (* dfs (p, v) visits the functions in depth-first order, applying v f
             * for function f to yield v', then visiting b's descendents,
             * then applying v' ().
             *)
            val dfs: t * (Function.t -> unit -> unit) -> unit
            val dropProfile: t -> t
            val layouts: t * (Layout.t -> unit) -> unit
            val layoutStats: t -> Layout.t
            val orderFunctions: t -> t
            val shrink: t -> t
            val shuffle: t -> t
            val toFile: {display: t Control.display, style: Control.style, suffix: string}
            val typeCheck: t -> unit
         end
   end
