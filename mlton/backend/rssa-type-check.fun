(* Copyright (C) 2009,2016-2017,2019-2022 Matthew Fluet.
 * Copyright (C) 1999-2008 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a HPND-style license.
 * See the file MLton-LICENSE for details.
 *)

functor RssaTypeCheck (S: RSSA_TYPE_CHECK_STRUCTS): RSSA_TYPE_CHECK =
struct

open S

structure Operand =
   struct
      open Operand

      val rec isLocation =
         fn Cast (z, _) => isLocation z
          | Offset _ => true
          | Runtime _ => true
          | SequenceOffset _ => true
          | _ => false
   end

local
   exception Violation
in
   fun wrapOper (oper: 'a -> unit) = fn (arg: 'a) =>
      (oper arg; true) handle Violation => false
   fun forcePoint (addHandler', isTop, lowerBoundPoint) = fn (e, p) =>
      let
         val () =
            addHandler'
            (e, fn v =>
             if isTop v then raise Violation else ())
      in
         lowerBoundPoint (e, p)
      end
end

structure ExnStack =
   struct
      local
      structure ZPoint =
         struct
            datatype t = Caller | Me

            val equals: t * t -> bool = op =

            val toString =
               fn Caller => "Caller"
                | Me => "Me"

            val layout = Layout.str o toString
         end
      structure L = FlatLatticeMono (structure Point = ZPoint
                                     val bottom = "Bottom"
                                     val top = "Top")
      open L
      in
      structure Point = ZPoint
      type t = t
      val layout = layout

      val newBottom = newBottom

      val op <= = fn args => wrapOper (op <=) args
      val lowerBoundPoint = fn args => wrapOper lowerBoundPoint args

      val forcePoint = fn (e, p) =>
         forcePoint (addHandler', Value.isTop, lowerBoundPoint) (e, p)

      val newPoint = fn p =>
         let
            val e = newBottom ()
            val _ = forcePoint (e, p)
         in
            e
         end
      val me = newPoint Point.Me
      end
   end

structure HandlerLat =
   struct
      local
      structure L = FlatLatticeMono (structure Point = Label
                                     val bottom = "Bottom"
                                     val top = "Top")
      open L
      in
      type t = t
      val layout = layout

      val newBottom = newBottom

      val op <= = fn args => wrapOper (op <=) args

      val forcePoint = fn (e, p) =>
         forcePoint (addHandler', Value.isTop, wrapOper lowerBoundPoint) (e, p)

      val newPoint = fn p =>
         let
            val e = newBottom ()
            val _ = forcePoint (e, p)
         in
            e
         end
      end
   end

structure HandlerInfo =
   struct
      datatype t = T of {block: Block.t,
                         global: ExnStack.t,
                         handler: HandlerLat.t,
                         slot: ExnStack.t,
                         visited: bool ref}

      fun new (b: Block.t): t =
         T {block = b,
            global = ExnStack.newBottom (),
            handler = HandlerLat.newBottom (),
            slot = ExnStack.newBottom (),
            visited = ref false}

      fun layout (T {global, handler, slot, ...}) =
         Layout.record [("global", ExnStack.layout global),
                        ("slot", ExnStack.layout slot),
                        ("handler", HandlerLat.layout handler)]
   end

val traceGoto =
   Trace.trace ("Rssa.checkHandlers.goto", Label.layout, Unit.layout)

fun checkHandlers (Program.T {functions, ...}) =
   let
      val debug = false
      fun checkFunction (f: Function.t): unit =
         let
            val {name, start, blocks, ...} = Function.dest f
            val {get = labelInfo: Label.t -> HandlerInfo.t,
                 rem = remLabelInfo,
                 set = setLabelInfo} =
               Property.getSetOnce
               (Label.plist, Property.initRaise ("info", Label.layout))
            val _ =
               Vector.foreach
               (blocks, fn b =>
                setLabelInfo (Block.label b, HandlerInfo.new b))
            (* Do a DFS of the control-flow graph. *)
            fun visitLabel l = visitInfo (labelInfo l)
            and visitInfo
               (hi as HandlerInfo.T {block, global, handler, slot,
                                     visited, ...}): unit =
               if !visited
                  then ()
               else
                  let
                     val _ = visited := true
                     val Block.T {label, statements, transfer, ...} = block
                     val _ =
                        if debug
                           then
                              let
                                 open Layout
                              in
                                 outputl
                                 (seq [str "visiting ",
                                       Label.layout label],
                                  Out.error)
                              end
                        else ()
                     datatype z = datatype Statement.t
                     val {global, handler, slot} =
                        Vector.fold
                        (statements,
                         {global = global, handler = handler, slot = slot},
                         fn (s, {global, handler, slot}) =>
                         case s of
                            SetExnStackLocal => {global = ExnStack.me,
                                                 handler = handler,
                                                 slot = slot}
                          | SetExnStackSlot => {global = slot,
                                                handler = handler,
                                                slot = slot}
                          | SetSlotExnStack => {global = global,
                                                handler = handler,
                                                slot = global}
                          | SetHandler l => {global = global,
                                             handler = HandlerLat.newPoint l,
                                             slot = slot}
                          | _ => {global = global,
                                  handler = handler,
                                  slot = slot})
                     fun fail msg =
                        (Control.message
                         (Control.Silent, fn () =>
                          let open Layout
                          in align
                             [str "before: ", HandlerInfo.layout hi,
                              str "block: ", Block.layout block,
                              seq [str "after: ",
                                   Layout.record
                                   [("global", ExnStack.layout global),
                                    ("slot", ExnStack.layout slot),
                                    ("handler",
                                     HandlerLat.layout handler)]],
                              Vector.layout
                              (fn Block.T {label, ...} =>
                               seq [Label.layout label,
                                    str " ",
                                    HandlerInfo.layout (labelInfo label)])
                              blocks]
                          end)
                         ; Error.bug (concat ["Rssa.checkHandlers: handler mismatch at ", msg]))
                     fun assert (msg, f) =
                        if f
                           then ()
                        else fail msg
                     fun goto (l: Label.t): unit =
                        let
                           val HandlerInfo.T {global = g, handler = h,
                                              slot = s, ...} =
                              labelInfo l
                           val _ =
                              assert ("goto",
                                      ExnStack.<= (global, g)
                                      andalso ExnStack.<= (slot, s)
                                      andalso HandlerLat.<= (handler, h))
                        in
                           visitLabel l
                        end
                     val goto = traceGoto goto
                     fun tail name =
                        assert (name,
                                ExnStack.forcePoint
                                (global, ExnStack.Point.Caller))
                     datatype z = datatype Transfer.t
                  in
                     case transfer of
                        CCall {return, ...} => Option.app (return, goto)
                      | Call {return, ...} =>
                           assert
                           ("return",
                            let
                               datatype z = datatype Return.t
                            in
                               case return of
                                  Dead => true
                                | NonTail {handler = h, ...} =>
                                     (case h of
                                         Handler.Caller =>
                                            ExnStack.forcePoint
                                            (global, ExnStack.Point.Caller)
                                       | Handler.Dead => true
                                       | Handler.Handle l =>
                                            let
                                               val res =
                                                  ExnStack.forcePoint
                                                  (global,
                                                   ExnStack.Point.Me)
                                                  andalso
                                                  HandlerLat.forcePoint
                                                  (handler, l)
                                               val _ = goto l
                                            in
                                               res
                                            end)
                                | Tail => true
                            end)
                      | Goto {dst, ...} => goto dst
                      | Spork {cont, spwn, ...} => (goto cont; goto spwn)
                      | Spoin {seq, sync, ...} => (goto seq; goto sync)
                      | Raise _ => tail "raise"
                      | Return _ => tail "return"
                      | Switch s => Switch.foreachLabel (s, goto)
                  end
            val info as HandlerInfo.T {global, ...} = labelInfo start
            val _ = ExnStack.lowerBoundPoint (global, ExnStack.Point.Caller)
            val _ = visitInfo info
            val _ =
               Control.diagnostics
               (fn display =>
                let
                   open Layout
                   val _ =
                      display (seq [str "checkHandlers ",
                                    Func.layout name])
                   val _ =
                      Vector.foreach
                      (blocks, fn Block.T {label, ...} =>
                       display (seq
                                [Label.layout label,
                                 str " ",
                                 HandlerInfo.layout (labelInfo label)]))
                in
                   ()
                end)
            val _ = Vector.foreach (blocks, fn b =>
                                    remLabelInfo (Block.label b))
         in
            ()
         end
      val _ = List.foreach (functions, checkFunction)
   in
      ()
   end

fun checkScopes (program as Program.T {functions, main, statics, ...}): unit =
   let
      datatype status =
         Defined
       | Global
       | InScope
       | Undefined
      fun make (layout, plist) =
         let
            val {get, set, ...} =
               Property.getSet (plist, Property.initConst Undefined)
            fun bind (x, isGlobal) =
               case get x of
                  Global => ()
                | Undefined =>
                     set (x, if isGlobal then Global else InScope)
                | _ => Error.bug ("Rssa.checkScopes: duplicate definition of "
                                  ^ (Layout.toString (layout x)))
            fun reference x =
               case get x of
                  Global => ()
                | InScope => ()
                | _ => Error.bug (concat
                                  ["Rssa.checkScopes: reference to ",
                                   Layout.toString (layout x),
                                   " not in scope"])
            fun unbind x =
               case get x of
                  Global => ()
                | _ => set (x, Defined)
         in (bind, reference, unbind)
         end
      val (bindSpid, getSpid, unbindSpid) = make (Spid.layout, Spid.plist)
      val (bindVar, getVar, unbindVar) = make (Var.layout, Var.plist)
      val bindVar =
         Trace.trace2
         ("Rssa.bindVar", Var.layout, Bool.layout, Unit.layout)
         bindVar
      val getVar =
         Trace.trace ("Rssa.getVar", Var.layout, Unit.layout) getVar
      val unbindVar =
         Trace.trace ("Rssa.unbindVar", Var.layout, Unit.layout) unbindVar
      val (bindFunc, _, _) = make (Func.layout, Func.plist)
      val bindFunc = fn f => bindFunc (f, false)
      val (bindLabel, getLabel, unbindLabel) =
         make (Label.layout, Label.plist)
      val bindLabel = fn l => bindLabel (l, false)
      fun loopStmt (s: Statement.t, isMain: bool): unit =
         (Statement.foreachUse (s, getVar)
          ; Statement.foreachDef (s, fn (x, _) =>
                                  bindVar (x, isMain)))
      fun loopFunc (f: Function.t, isMain: bool): unit =
         let
            val bindVar = fn x => bindVar (x, isMain)
            val {args, blocks, start, ...} = Function.dest f
            val _ = Vector.foreach (args, bindVar o #1)
            val _ = Vector.foreach (blocks, bindLabel o Block.label)
            val _ = getLabel start
            val _ =
               Vector.foreach
               (blocks, fn Block.T {transfer, ...} =>
                Transfer.foreachLabel (transfer, getLabel))
            (* Descend the dominator tree, verifying that variable
             * definitions dominate variable uses.
             *)
            val _ =
               Tree.traverse
               (Function.dominatorTree f,
                fn Block.T {args, statements, transfer, ...} =>
                let
                   val _ = Vector.foreach (args, bindVar o #1)
                   val _ =
                      Vector.foreach
                      (statements, fn s => loopStmt (s, isMain))
                   val _ = Transfer.foreachUse (transfer, getVar)
                   val _ = (case transfer of
                               Transfer.Spork {spid, ...} => bindSpid (spid, false)
                             | Transfer.Spoin {spid, ...} => getSpid spid
                             | _ => ())
                in
                   fn () =>
                   if isMain
                      then ()
                   else
                      let
                         val _ = (case transfer of
                                     Transfer.Spork {spid, ...} => unbindSpid spid
                                   | _ => ())
                         val _ =
                            Vector.foreach
                            (statements, fn s =>
                             Statement.foreachDef (s, unbindVar o #1))
                         val _ = Vector.foreach (args, unbindVar o #1)
                      in
                         ()
                      end
                end)
            val _ = Vector.foreach (blocks, unbindLabel o Block.label)
            val _ = Vector.foreach (args, unbindVar o #1)
         in
            ()
         end
      val _ = Vector.foreach (statics, fn {dst, obj} =>
                              loopStmt (Statement.Object {dst = dst, obj = obj}, true))
      val _ = List.foreach (functions, bindFunc o Function.name)
      val _ = loopFunc (main, true)
      val _ = List.foreach (functions, fn f => loopFunc (f, false))
      val _ = Program.clear program
   in ()
   end

val checkScopes = Control.trace (Control.Detail, "checkScopes") checkScopes

fun checkSpork (program as Program.T {functions, main, ...}): unit =
   let
      fun checkFunction (f: Function.t): unit =
         let
            val {start, blocks, ...} = Function.dest f
            val {get = labelInfo, rem, set = setLabelInfo, ...} =
               Property.getSetOnce
               (Label.plist,
                Property.initRaise ("Rssa.TypeCheck.checkSpork.info", Label.layout))
            val _ = Vector.foreach (blocks, fn b =>
                                    setLabelInfo (Block.label b,
                                                  {block = b,
                                                   sporkInfo = ref NONE}))
            fun goto (l: Label.t,
                      inSpwn: int,
                      sporkNest: Spid.t list) =
               let
                  fun bug (msg: string): 'a =
                     Error.bug
                     (concat ["Rssa.TypeCheck.checkSpork: bug found in ", Label.toString l,
                              ": ", msg])
                  val {block, sporkInfo} = labelInfo l
               in
                  case (!sporkInfo) of
                     NONE =>
                        let
                           val _ = sporkInfo := SOME {inSpwn = inSpwn, sporkNest = sporkNest}
                           val Block.T {transfer, ...} = block
                           fun simple l = goto (l, inSpwn, sporkNest)
                           fun checkLeave () =
                              let
                                 val _ =
                                    if inSpwn > 0
                                       then bug "may not leave function within Spork/spwn"
                                       else ()
                                 val _ =
                                    case sporkNest of
                                       [] => ()
                                     | _ => bug "nonempty sporkNest when leaving function"
                              in
                                 ()
                              end
                           datatype z = datatype Transfer.t
                        in
                           case transfer of
                              Call {return, ...} =>
                                 let
                                    datatype z = datatype Return.t
                                 in
                                    case return of
                                       Dead => ()
                                     | NonTail {handler, cont, ...} =>
                                          let
                                             datatype z = datatype Handler.t
                                          in
                                             simple cont
                                             ; (case handler of
                                                   Dead => ()
                                                 | Handle hndl => simple hndl
                                                 | Caller => checkLeave ())
                                          end
                                     | Tail => checkLeave ()
                                 end
                            | Raise _ => checkLeave ()
                            | Return _ => checkLeave ()
                            | Spork {spid, cont, spwn} =>
                                 (goto (cont, inSpwn, spid::sporkNest)
                                  ; goto (spwn, inSpwn + 1, []))
                            | Spoin {spid, seq, sync} =>
                                 (case (sporkNest) of
                                     [] => bug "empty sporkNest at Spoin"
                                   | spid'::sporkNest' =>
                                        if Spid.equals (spid, spid')
                                           then (goto (seq, inSpwn, sporkNest')
                                                 ; goto (sync, inSpwn, sporkNest'))
                                           else bug "mismatched sporkNest at Spoin")
                            | _ => Transfer.foreachLabel (transfer, simple)
                        end
                   | SOME {inSpwn = inSpwn', sporkNest = sporkNest'} =>
                        let
                           val _ = if Int.equals (inSpwn, inSpwn')
                                      then ()
                                      else bug "mismatched block: inSpwn"
                           val _ = if List.equals (sporkNest, sporkNest', Spid.equals)
                                      then ()
                                      else bug "mismatched block: sporkNest"
                        in
                           ()
                        end
               end
            val _ = goto (start, 0, [])
            val _ = Vector.foreach (blocks, fn Block.T {label, ...} => rem label)
         in
            ()
         end
      val _ = checkFunction main
      val _ = List.foreach (functions, checkFunction)
   in ()
   end

val checkSpork = Control.trace (Control.Detail, "checkSpork") checkSpork

fun typeCheck (p as Program.T {functions, main, objectTypes, profileInfo, statics, ...}) =
   let
      val _ =
         Vector.foreach
         (objectTypes, fn ty =>
          Err.check ("objectType",
                     fn () => ObjectType.isOk ty,
                     fn () => ObjectType.layout ty))
      fun tyconTy (opt: ObjptrTycon.t): ObjectType.t =
         Vector.sub (objectTypes, ObjptrTycon.index opt)
      val () = checkScopes p
      val checkFrameSourceSeqIndex =
         case profileInfo of
            NONE => (fn _ => ())
          | SOME {sourceMaps, getFrameSourceSeqIndex} =>
            let
               val _ =
                  Err.check
                  ("sourceMaps",
                   fn () => SourceMaps.check sourceMaps,
                   fn () => SourceMaps.layout sourceMaps)
            in
               fn (l, k) => let
                               fun chk b =
                                  Err.check
                                  ("getFrameSourceSeqIndex",
                                   fn () => (case (b, getFrameSourceSeqIndex l) of
                                                (true, SOME ssi) =>
                                                   SourceMaps.checkSourceSeqIndex
                                                   (sourceMaps, ssi)
                                              | (false, NONE) => true
                                              | _ => false),
                                   fn () => Label.layout l)
                            in
                               case k of
                                  Kind.Cont _ => chk true
                                | Kind.CReturn _ => chk true
                                | Kind.Handler => chk true
                                | Kind.Jump => chk false
                                | Kind.SporkSpwn _ => chk true
                                | Kind.SpoinSync _ => chk false
                            end
            end
      val {get = labelBlock: Label.t -> Block.t,
           set = setLabelBlock, ...} =
         Property.getSetOnce (Label.plist,
                              Property.initRaise ("block", Label.layout))
      val {get = funcInfo, set = setFuncInfo, ...} =
         Property.getSetOnce (Func.plist,
                              Property.initRaise ("info", Func.layout))
      val {get = varType: Var.t -> Type.t, set = setVarType, ...} =
         Property.getSetOnce (Var.plist,
                              Property.initRaise ("type", Var.layout))
      val setVarType =
         Trace.trace2 ("Rssa.setVarType", Var.layout, Type.layout,
                       Unit.layout)
         setVarType
      fun checkOperandAux (x: Operand.t, isLHS): unit =
          let
             datatype z = datatype Operand.t
             fun ok () =
                case x of
                   Cast (z, ty) =>
                      (checkOperandAux (z, isLHS)
                       ; Type.castIsOk {from = Operand.ty z,
                                        to = ty,
                                        tyconTy = tyconTy})
                 | Const _ => true
                 | GCState => true
                 | Offset {base, offset, ty} =>
                      (checkOperandAux (base, false)
                       ; Type.offsetIsOk {base = Operand.ty base,
                                          mustBeMutable = isLHS,
                                          offset = offset,
                                          tyconTy = tyconTy,
                                          result = ty})
                 | ObjptrTycon _ => true
                 | Runtime _ => true
                 | SequenceOffset {base, index, offset, scale, ty} =>
                      (checkOperandAux (base, false)
                       ; checkOperandAux (index, false)
                       ; Type.sequenceOffsetIsOk {base = Operand.ty base,
                                                  index = Operand.ty index,
                                                  mustBeMutable = isLHS,
                                                  offset = offset,
                                                  tyconTy = tyconTy,
                                                  result = ty,
                                                  scale = scale})
                 | Var {ty, var} => Type.isSubtype (varType var, ty)
                 | Address z =>
                      (checkOperandAux (z, isLHS)
                       ; (case z of
                             Offset _ => true
                           | SequenceOffset _ => true
                           | _ => false))
          in
             Err.check ("operand", ok, fn () => Operand.layout x)
          end
      val checkOperandAux =
         Trace.trace2 ("Rssa.checkOperandAux",
                       Operand.layout, Bool.layout, Unit.layout)
         checkOperandAux
      fun checkLhsOperand z = checkOperandAux (z, true)
      fun checkOperand z = checkOperandAux (z, false)
      fun checkOperands v = Vector.foreach (v, checkOperand)
      fun check' (x, name, isOk, layout) =
         Err.check (name, fn () => isOk x, fn () => layout x)
      val handlersImplemented = ref false
      val labelKind = Block.kind o labelBlock
      fun statementOk (s: Statement.t): bool =
         let
            datatype z = datatype Statement.t
         in
            case s of
               Bind {src, dst = (_, dstTy), ...} =>
                  (checkOperand src
                   ; Type.isSubtype (Operand.ty src, dstTy))
             | Move {dst, src} =>
                  (checkLhsOperand dst
                   ; checkOperand src
                   ; (Type.isSubtype (Operand.ty src, Operand.ty dst)
                      andalso Operand.isLocation dst))
             | Object {dst = (_, dstTy), obj} =>
                  (Object.isOk (obj, {checkUse = checkOperand,
                                      tyconTy = tyconTy})
                   andalso Type.isSubtype (Object.ty obj, dstTy))
             | PrimApp {args, dst, prim} =>
                  (Vector.foreach (args, checkOperand)
                   ; (Type.checkPrimApp
                      {args = Vector.map (args, Operand.ty),
                       prim = prim,
                       result = Option.map (dst, #2)}))
             | Profile _ => true
             | SetExnStackLocal => (handlersImplemented := true; true)
             | SetExnStackSlot => (handlersImplemented := true; true)
             | SetHandler l =>
                  (handlersImplemented := true;
                   case labelKind l of
                      Kind.Handler => true
                    | _ => false)
             | SetSlotExnStack => (handlersImplemented := true; true)
         end
      val statementOk =
         Trace.trace ("Rssa.statementOk",
                      Statement.layout,
                      Bool.layout)
                     statementOk
      fun gotoOk {args: Type.t vector,
                  dst: Label.t}: bool =
         let
            val Block.T {args = formals, kind, ...} = labelBlock dst
         in
            Vector.equals (args, formals, fn (t, (_, t')) =>
                           Type.isSubtype (t, t'))
            andalso (case kind of
                        Kind.Jump => true
                      | _ => false)
         end
      fun labelIsNullaryJump l = gotoOk {dst = l, args = Vector.new0 ()}
      fun tailIsOk (caller: Type.t vector option,
                    callee: Type.t vector option): bool =
         case (caller, callee) of
            (_, NONE) => true
          | (SOME caller, SOME callee) =>
               Vector.equals (callee, caller, Type.isSubtype)
          | _ => false
      fun nonTailIsOk (formals: (Var.t * Type.t) vector,
                       returns: Type.t vector option): bool =
         case returns of
            NONE => true
          | SOME ts =>
               Vector.equals (formals, ts, fn ((_, t), t') =>
                              Type.isSubtype (t', t))
      fun callIsOk {args, func, raises, return, returns} =
         let
            val {args = formals,
                 raises = raises',
                 returns = returns', ...} =
               Function.dest (funcInfo func)
         in
            Vector.equals (args, formals, fn (z, (_, t)) =>
                           Type.isSubtype (Operand.ty z, t))
            andalso
            (case return of
                Return.Dead =>
                   Option.isNone raises'
                   andalso Option.isNone returns'
              | Return.NonTail {cont, handler} =>
                   let
                      val Block.T {args = cArgs, kind = cKind, ...} =
                         labelBlock cont
                   in
                      nonTailIsOk (cArgs, returns')
                      andalso
                      (case cKind of
                          Kind.Cont {handler = h} =>
                             Handler.equals (handler, h)
                             andalso
                             (case h of
                                 Handler.Caller =>
                                    tailIsOk (raises, raises')
                               | Handler.Dead => true
                               | Handler.Handle l =>
                                    let
                                       val Block.T {args = hArgs,
                                                    kind = hKind, ...} =
                                          labelBlock l
                                    in
                                       nonTailIsOk (hArgs, raises')
                                       andalso
                                       (case hKind of
                                           Kind.Handler => true
                                         | _ => false)
                                    end)
                        | _ => false)
                   end
              | Return.Tail =>
                   tailIsOk (raises, raises')
                   andalso tailIsOk (returns, returns'))
         end

      fun sporkIsOk {spid, cont, spwn} =
         gotoOk {args = Vector.new0 (), dst = cont}
         andalso
         let
            val Block.T {kind, ...} = labelBlock spwn
         in
            case kind of
               Kind.SporkSpwn {spid = spid'} =>
                  Spid.equals (spid, spid')
             | _ => false
         end

      fun spoinIsOk {spid, seq, sync} =
         gotoOk {args = Vector.new0 (), dst = seq}
         andalso
         let
            val Block.T {kind, ...} = labelBlock sync
         in
            case kind of
               Kind.SpoinSync {spid = spid'} =>
                  Spid.equals (spid, spid')
             | _ => false
         end

      fun checkFunction f =
         let
            val {args, blocks, raises, returns, start, ...} = Function.dest f
            val _ = Vector.foreach (args, setVarType)
            val _ =
               Vector.foreach
               (blocks, fn b as Block.T {args, kind, label, statements, ...} =>
                (setLabelBlock (label, b)
                 ; checkFrameSourceSeqIndex (label, kind)
                 ; Vector.foreach (args, setVarType)
                 ; Vector.foreach (statements, fn s =>
                                   Statement.foreachDef
                                   (s, setVarType))))
            val _ = check' (start, "start", labelIsNullaryJump, Label.layout)
            fun transferOk (t: Transfer.t): bool =
               let
                  datatype z = datatype Transfer.t
               in
                  case t of
                     CCall {args, func, return} =>
                        let
                           val _ = checkOperands args
                        in
                           CFunction.isOk (func, {isUnit = Type.isUnit})
                           andalso
                           Vector.equals (args, CFunction.args func,
                                          fn (z, t) =>
                                          Type.isSubtype
                                          (Operand.ty z, t))
                           andalso
                           case return of
                              NONE => true
                            | SOME l =>
                                 case labelKind l of
                                    Kind.CReturn {func = f} =>
                                       CFunction.equals (func, f)
                                  | _ => false
                        end
                   | Call {args, func, return} =>
                        let
                           val _ = checkOperands args
                        in
                           callIsOk {args = args,
                                     func = func,
                                     raises = raises,
                                     return = return,
                                     returns = returns}
                        end
                   | Goto {args, dst} =>
                        (checkOperands args
                         ; gotoOk {args = Vector.map (args, Operand.ty),
                                   dst = dst})
                   | Spork x =>
                        sporkIsOk x
                   | Spoin x =>
                        spoinIsOk x
                   | Raise zs =>
                        (checkOperands zs
                         ; (case raises of
                               NONE => false
                             | SOME ts =>
                                  Vector.equals
                                  (zs, ts, fn (z, t) =>
                                   Type.isSubtype (Operand.ty z, t))))
                   | Return zs =>
                        (checkOperands zs
                         ; (case returns of
                               NONE => false
                             | SOME ts =>
                                  Vector.equals
                                  (zs, ts, fn (z, t) =>
                                   Type.isSubtype (Operand.ty z, t))))
                   | Switch s =>
                        Switch.isOk (s, {checkUse = checkOperand,
                                         labelIsOk = labelIsNullaryJump})
               end
            val transferOk =
               Trace.trace ("Rssa.transferOk",
                            Transfer.layout,
                            Bool.layout)
               transferOk
            fun blockOk (Block.T {args, kind, statements, transfer, ...})
               : bool =
               let
                  fun kindOk (k: Kind.t): bool =
                     let
                        datatype z = datatype Kind.t
                     in
                        case k of
                           Cont _ => true
                         | CReturn {func} =>
                              let
                                 val return = CFunction.return func
                              in
                                 0 = Vector.length args
                                 orelse
                                 (1 = Vector.length args
                                  andalso
                                  let
                                     val expects =
                                        #2 (Vector.first args)
                                  in
                                     Type.isSubtype (return, expects)
                                     andalso
                                     CType.equals (Type.toCType return,
                                                   Type.toCType expects)
                                  end)
                              end
                         | Handler => true
                         | Jump => true
                         | SporkSpwn _ =>
                              1 = Vector.length args
                              andalso
                              Type.isObjptr (#2 (Vector.first args))
                         | SpoinSync _ =>
                              1 = Vector.length args
                              andalso
                              Type.isObjptr (#2 (Vector.first args))
                     end
                  val _ = check' (kind, "kind", kindOk, Kind.layout)
                  val _ =
                     Vector.foreach
                     (statements, fn s =>
                      check' (s, "statement", statementOk,
                              Statement.layout))
                  val _ = check' (transfer, "transfer", transferOk,
                                  Transfer.layout)
               in
                  true
               end
            val blockOk =
               Trace.trace ("Rssa.blockOk",
                            Block.layout,
                            Bool.layout)
                           blockOk

            val _ =
               Vector.foreach
               (blocks, fn b =>
                check' (b, "block", blockOk, Block.layout))
         in
            ()
         end
      val _ =
         Vector.foreach
         (statics, fn stmt as {dst, ...} =>
          (setVarType dst
           ; check' (Statement.Object stmt, "static", statementOk, Statement.layout)))
      val _ =
         List.foreach
         (functions, fn f => setFuncInfo (Function.name f, f))
      val _ = checkFunction main
      val _ = List.foreach (functions, checkFunction)
      val _ =
         check'
         (main, "main function",
          fn f =>
          let
             val {args, ...} = Function.dest f
          in
             Vector.isEmpty args
          end,
          Function.layout)
      val _ = Program.clear p
      val _ = if !handlersImplemented
                 then checkHandlers p
                 else ()
      val _ = checkSpork p
   in
      ()
   end handle Err.E e => (Layout.outputl (Err.layout e, Out.error)
                          ; Error.bug "Rssa.typeCheck")
end
