------------------------------------------------------------------------------
--                                  G P S                                   --
--                                                                          --
--                     Copyright (C) 2004-2013, AdaCore                     --
--                                                                          --
-- This is free software;  you can redistribute it  and/or modify it  under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  This software is distributed in the hope  that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General  Public  License  distributed  with  this  software;   see  file --
-- COPYING3.  If not, go to http://www.gnu.org/licenses for a complete copy --
-- of the license.                                                          --
------------------------------------------------------------------------------

with GPS.Kernel.Hooks;          use GPS.Kernel.Hooks;
with GPS.Kernel.Scripts;        use GPS.Kernel.Scripts;
with Src_Editor_Box;            use Src_Editor_Box;
with Src_Editor_Module;         use Src_Editor_Module;
with Ada.Text_IO; use Ada.Text_IO;

package body Src_Editor_Buffer.Hooks is

   type Src_File_Location_Hooks_Args is new File_Location_Hooks_Args with
     null record;
   overriding procedure Destroy (Data : in out Src_File_Location_Hooks_Args);
   --  See inherited documentation

   --------------------------
   -- Create_Callback_Data --
   --------------------------

   overriding function Create_Callback_Data
     (Script : access GNATCOLL.Scripts.Scripting_Language_Record'Class;
      Hook   : Hook_Name;
      Data   : access File_Edition_Hooks_Args)
      return GNATCOLL.Scripts.Callback_Data_Access
   is
      F : constant Class_Instance :=
         GPS.Kernel.Scripts.Create_File (Script, Data.File);
      D : constant Callback_Data_Access :=
        new Callback_Data'Class'(Create (Script, 3));
   begin
      Set_Nth_Arg (D.all, 1, To_String (Hook));
      Set_Nth_Arg (D.all, 2, F);
      Set_Nth_Arg (D.all, 3, Integer (Data.Character));
      return D;
   end Create_Callback_Data;

   -------------
   -- Destroy --
   -------------

   overriding procedure Destroy (Data : in out Src_File_Location_Hooks_Args) is
   begin
      null;
   end Destroy;

   ----------------------
   -- Location_Changed --
   ----------------------

   procedure Location_Changed (Buffer : Source_Buffer) is
      Data : aliased Src_File_Location_Hooks_Args :=
               (Hooks_Data with
                File          => Buffer.Filename,
                Line          => 0,
                Column        => 0);
      Box : constant Source_Editor_Box := Get_Source_Box_From_MDI
        (Find_Editor (Get_Kernel (Buffer), Buffer.Filename));
   begin
      if Box /= null then
         Get_Cursor_Position
           (Get_Buffer (Box), Editable_Line_Type (Data.Line),
            Character_Offset_Type (Data.Column));
         Run_Hook (Buffer.Kernel, Location_Changed_Hook,
                   Data'Unchecked_Access);
         Destroy (Data);
      end if;
   end Location_Changed;

   ----------------
   -- Word_Added --
   ----------------

   procedure Word_Added (Buffer : Source_Buffer) is
      Data : aliased  File_Hooks_Args :=
               (Hooks_Data with File => Buffer.Filename);
   begin
      Run_Hook (Buffer.Kernel, Word_Added_Hook, Data'Unchecked_Access);
   end Word_Added;

   ---------------------
   -- Character_Added --
   ---------------------

   procedure Character_Added
     (Buffer      : Source_Buffer;
      Character   : Gunichar;
      Interactive : Boolean)
   is
      Data : aliased File_Edition_Hooks_Args :=
        (Hooks_Data
         with File   => Buffer.Filename,
         Character   => Character,
         Interactive => Interactive);
   begin
      Put_Line ("IN CHAR ADDED");
      Run_Hook
        (Buffer.Kernel, Character_Added_Hook, Data'Unchecked_Access);
   end Character_Added;

   ---------------------
   -- Buffer_Modified --
   ---------------------

   procedure Buffer_Modified (Buffer : Source_Buffer) is
      Data : aliased  File_Hooks_Args :=
               (Hooks_Data with File => Buffer.Filename);
   begin
      Run_Hook
        (Buffer.Kernel, Buffer_Modified_Hook, Data'Unchecked_Access);
   end Buffer_Modified;

   ---------------------------
   -- Register_Editor_Hooks --
   ---------------------------

   procedure Register_Editor_Hooks
     (Kernel : access GPS.Kernel.Kernel_Handle_Record'Class) is
   begin
      Register_Hook_No_Return
        (Kernel, Location_Changed_Hook, File_Location_Hook_Type);
      Register_Hook_No_Return
        (Kernel, Word_Added_Hook, File_Location_Hook_Type);
      Register_Hook_No_Return
        (Kernel, Character_Added_Hook, File_Edition_Hook_Type);
   end Register_Editor_Hooks;

end Src_Editor_Buffer.Hooks;
