------------------------------------------------------------------------------
--                               GNAT Studio                                --
--                                                                          --
--                       Copyright (C) 2019, AdaCore                        --
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

--  Here are items which are needed from Language Server:
--    - Entity name
--    - Reference_Kind
--    - Caller
--    - List of real reference kinds for an entity
--    - all entities in project/file

with Ada.Strings.Unbounded;      use Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;

with GNATCOLL.Scripts;
with GNATCOLL.VFS;
with GNATCOLL.Utils;             use GNATCOLL.Utils;

with Gtk.Box;                    use Gtk.Box;
with Gtk.Button;                 use Gtk.Button;
with Gtk.Check_Button;           use Gtk.Check_Button;
with Gtk.Dialog;                 use Gtk.Dialog;
with Gtk.Enums;                  use Gtk.Enums;
with Gtk.Frame;                  use Gtk.Frame;
with Gtk.Radio_Button;           use Gtk.Radio_Button;
with Gtk.Stock;
with Gtk.Vbutton_Box;            use Gtk.Vbutton_Box;
with Gtk.Widget;                 use Gtk.Widget;
with Glib.Convert;               use Glib.Convert;

with Gtkada.Handlers;            use Gtkada.Handlers;

with GPS.Default_Styles;         use GPS.Default_Styles;
with GPS.Editors;
with GPS.Kernel.Actions;         use GPS.Kernel.Actions;
with GPS.Kernel.Contexts;        use GPS.Kernel.Contexts;
with GPS.Kernel.Entities;
with GPS.Kernel.Messages;        use GPS.Kernel.Messages;
with GPS.Kernel.Messages.Markup;
with GPS.Kernel.Modules.UI;
with GPS.Kernel.Scripts;
with GPS.Location_View;
with GPS.LSP_Module;
with GPS.LSP_Client.Requests.References;
with GPS.LSP_Client.Utilities;   use GPS.LSP_Client.Utilities;
with GPS.Scripts.Commands;

with Commands;                   use Commands;
with Commands.Interactive;       use Commands.Interactive;
with Histories;
with Language.Ada;
with Src_Editor_Module.Shell;

with Basic_Types;                use Basic_Types;
with LSP.JSON_Streams;
with LSP.Messages;
with LSP.Types;
with String_Utils;               use String_Utils;
with UTF8_Utils;

package body GPS.LSP_Client.References is

   type Find_Refs_Command (Locals_Only : Boolean; Specific : Boolean) is
     new Interactive_Command with null record;
   overriding function Execute
     (Command : access Find_Refs_Command;
      Context : Interactive_Command_Context) return Command_Return_Type;
   --  Find references command which calls LSP or old implementation.

   type Has_Entity_Name_Filter is new Action_Filter_Record with null record;
   overriding function Filter_Matches_Primitive
     (Filter  : access Has_Entity_Name_Filter;
      Context : GPS.Kernel.Selection_Context) return Boolean;
   --  True if the current entity is an access type.

   type Result_Filter is record
      Ref_Kinds : LSP.Types.LSP_String_Vector;
      --  The reference kinds' name that should be displayed.
   end record;
   --  Will be used for filtering results

   -- References_Command --

   type References_Command is
     new Abstract_References_Command with record
      Locations : LSP.Messages.Location_Vector;
   end record;
   type Ref_Command_Access is access all References_Command'Class;
   --  Used to transfer references lists via python API

   overriding function Execute
     (Command : access References_Command)
      return Command_Return_Type is (Failure);

   overriding procedure Get_Result
     (Self : not null access References_Command;
      Data : in out GNATCOLL.Scripts.Callback_Data'Class);

   -- References_Request --

   type References_Request is
     new GPS.LSP_Client.Requests.References.Abstract_References_Request with
      record
         Kernel      : Kernel_Handle;
         Title       : Unbounded_String;
         Name        : Unbounded_String;
         From_File   : GNATCOLL.VFS.Virtual_File;
         Show_Caller : Boolean := False;
         Filter      : Result_Filter;
         Command     : Ref_Command_Access;
      end record;
   type References_Request_Access is access all References_Request;
   --  Used for communicate with LSP

   overriding procedure Finalize (Self : in out References_Request);

   overriding procedure On_Result_Message
     (Self   : in out References_Request;
      Result : LSP.Messages.Location_Vector);

   -- Others --

   function All_Refs_Category
     (Entity             : String;
      Line               : Integer;
      Local_Only         : Boolean;
      Local_File         : GNATCOLL.VFS.Virtual_File;
      All_From_Same_File : Boolean)
      return String;
   --  Return a suitable category for references action messages.

   type Filters_Buttons is array (Natural range <>) of Gtk_Check_Button;
   type Filters_Buttons_Access is access Filters_Buttons;
   type References_Filter_Dialog_Record is new Gtk_Dialog_Record with record
      Filters : Filters_Buttons_Access;
   end record;
   type References_Filter_Dialog is access all
     References_Filter_Dialog_Record'Class;

   procedure Unchecked_Free is new Ada.Unchecked_Deallocation
     (Filters_Buttons, Filters_Buttons_Access);

   procedure Unselect_All_Filters (Dialog : access Gtk_Widget_Record'Class);
   procedure Select_All_Filters (Dialog : access Gtk_Widget_Record'Class);
   --  Select or unselect all filters in "Find references..."

   procedure Find_All_Refs
     (Kernel   : Kernel_Handle;
      File     : GNATCOLL.VFS.Virtual_File;
      Line     : Integer;
      Column   : Basic_Types.Visible_Column_Type;
      Name     : String;
      Implicit : Boolean;
      In_File  : GNATCOLL.VFS.Virtual_File;
      Data     : GNATCOLL.Scripts.Callback_Data_Access);
   --  Implements GPS.EditorBuffer.find_all_refs and
   --  GPS.EditorBuffer.references python API

   function All_Reference_Kinds return LSP.Types.LSP_String_Vector;
   --  Returns list of all supported reference kinds.

   Message_Flag : constant Message_Flags :=
     (Editor_Side => True,
      Editor_Line => False,
      Locations   => True);

   -----------------------
   -- All_Refs_Category --
   -----------------------

   function All_Refs_Category
     (Entity             : String;
      Line               : Integer;
      Local_Only         : Boolean;
      Local_File         : GNATCOLL.VFS.Virtual_File;
      All_From_Same_File : Boolean)
      return String is
   begin
      if All_From_Same_File then
         return "Entities imported into " &
           GNATCOLL.VFS."+"(Local_File.Base_Name);

      elsif Local_Only then
         return "Local references for "
           & Entity
           & " ("  & Local_File.Display_Base_Name
           & ":" & String_Utils.Image (Line) & ") " & "in "
           & (Local_File.Display_Base_Name);

      else
         return "References for " & Entity
           & " (" & Local_File.Display_Base_Name
           & ":" & String_Utils.Image (Line) & ")";
      end if;
   end All_Refs_Category;

   -------------------------
   -- All_Reference_Kinds --
   -------------------------

   function All_Reference_Kinds return LSP.Types.LSP_String_Vector is
      All_Flags   : constant LSP.Messages.AlsReferenceKind_Set :=
                      (Is_Server_Side => True, As_Flags => (others => True));
      All_Strings : LSP.Messages.AlsReferenceKind_Set;
      JS          : aliased LSP.JSON_Streams.JSON_Stream;

   begin
      LSP.Messages.AlsReferenceKind_Set'Write (JS'Access, All_Flags);
      JS.Set_JSON_Document (JS.Get_JSON_Document);
      LSP.Messages.AlsReferenceKind_Set'Read (JS'Access, All_Strings);

      return All_Strings.As_Strings;
   end All_Reference_Kinds;

   -------------
   -- Execute --
   -------------

   overriding function Execute
     (Command : access Find_Refs_Command;
      Context : Interactive_Command_Context) return Command_Return_Type
   is
      Kernel : constant Kernel_Handle := Get_Kernel (Context.Context);
      Lang   : Standard.Language.Language_Access;
      File   : GNATCOLL.VFS.Virtual_File;
      Title  : Unbounded_String;
   begin
      File := File_Information (Context.Context);
      Lang := Kernel.Get_Language_Handler.Get_Language_From_File (File);

      if GPS.LSP_Module.LSP_Is_Enabled (Lang) then
         Title := To_Unbounded_String
           (All_Refs_Category
              (Entity             => Entity_Name_Information (Context.Context),
               Line               =>
                 (if Has_Entity_Line_Information (Context.Context) then
                     Integer (Entity_Line_Information (Context.Context))
                  else
                     Line_Information (Context.Context)),
               Local_Only         => Command.Locals_Only,
               Local_File         => File,
               All_From_Same_File => Command.Specific));

         if Command.Specific then
            declare
               All_Refs           : constant LSP.Types.LSP_String_Vector :=
                                      All_Reference_Kinds;
               Dialog             : References_Filter_Dialog;
               Box                : Gtk_Box;
               Col                : array (1 .. 2) of Gtk_Box;
               Filter_Box         : Gtk_Vbutton_Box;
               Index              : Integer := Col'First;
               Project_And_Recursive,
               File_Only          : Gtk_Radio_Button;
               Show_Caller        : Gtk_Check_Button;
--  will be used when we have all entities from the file
--                 From_Same_File     : Gtk_Radio_Button;
               Include_Overriding : Gtk_Check_Button;
               Frame              : Gtk_Frame;
               Ignore             : Gtk_Widget;
               Button             : Gtk_Button;

            begin
               Dialog := new References_Filter_Dialog_Record;
               Dialog.Filters :=
                 new Filters_Buttons (1 .. Natural (All_Refs.Length));

               Initialize
                 (Dialog,
                  Title  => "Find References Options",
                  Parent => Kernel.Get_Main_Window,
                  Flags  => Modal
                  or Use_Header_Bar_From_Settings (Kernel.Get_Main_Window));

               --  Context choice

               Gtk_New (Frame, "Context");
               Pack_Start (Get_Content_Area (Dialog), Frame);
               Gtk_New_Vbox (Box, Homogeneous => True);
               Add (Frame, Box);

               Gtk_New (Project_And_Recursive, Widget_SList.Null_List,
                        "In all projects");
               Pack_Start (Box, Project_And_Recursive);
               Histories.Create_New_Boolean_Key_If_Necessary
                 (Get_History (Kernel).all,
                  "Find_Prefs_Project_Recursive",
                  True);
               Histories.Associate
                 (Get_History (Kernel).all,
                  "Find_Prefs_Project_Recursive",
                  Project_And_Recursive);

               Gtk_New (File_Only, Get_Group (Project_And_Recursive),
                        "In current file");
               Pack_Start (Box, File_Only);
               Histories.Create_New_Boolean_Key_If_Necessary
                 (Get_History (Kernel).all, "Find_Prefs_File_Only", False);
               Histories.Associate
                 (Get_History (Kernel).all, "Find_Prefs_File_Only", File_Only);

--  will be used when we all entities from the file
--                 Gtk_New
--                   (From_Same_File, Get_Group (Project_And_Recursive),
--                    "All entities imported from same file");
--                 Pack_Start (Box, From_Same_File);
--                 Histories.Create_New_Boolean_Key_If_Necessary
--                   (Get_History (Kernel).all,
--                    "Find_Prefs_From_Same_File",
--                    False);
--                 Histories.Associate
--                   (Get_History (Kernel).all, "Find_Prefs_From_Same_File",
--                    From_Same_File);

               --  Filter choice

               Gtk_New (Frame, "Filter");
               Pack_Start (Get_Content_Area (Dialog), Frame);
               Gtk_New_Hbox (Box, Homogeneous => False);
               Add (Frame, Box);

               for C in Col'Range loop
                  Gtk_New_Vbox (Col (C), Homogeneous => True);
                  Pack_Start (Box, Col (C), Expand => True);
               end loop;

               for F in Dialog.Filters'Range loop
                  Gtk_New
                    (Dialog.Filters (F),
                     LSP.Types.To_UTF_8_String (All_Refs (F)));
                  Pack_Start (Col (Index), Dialog.Filters (F));
                  Histories.Create_New_Boolean_Key_If_Necessary
                    (Get_History (Kernel).all,
                     Histories.History_Key
                       ("Find_Prefs_Filter_" & F'Img), True);
                  Histories.Associate
                    (Get_History (Kernel).all,
                     Histories.History_Key ("Find_Prefs_Filter_" & F'Img),
                     Dialog.Filters (F));
                  Index := Index + 1;
                  if Index > Col'Last then
                     Index := Col'First;
                  end if;
               end loop;

               Gtk_New (Filter_Box);
               Set_Layout (Filter_Box, Buttonbox_Spread);
               Pack_Start (Box, Filter_Box, Padding => 5);

               Gtk_New (Button, "Select all");
               Pack_Start (Filter_Box, Button);
               Widget_Callback.Object_Connect
                 (Button, Signal_Clicked, Select_All_Filters'Access, Dialog);

               Gtk_New (Button, "Unselect all");
               Pack_Start (Filter_Box, Button);
               Widget_Callback.Object_Connect
                 (Button, Signal_Clicked, Unselect_All_Filters'Access, Dialog);

               --  Extra info choice

               Gtk_New (Frame, "Advanced Search");
               Pack_Start (Get_Content_Area (Dialog), Frame);
               Gtk_New_Vbox (Box, Homogeneous => True);
               Add (Frame, Box);

               Gtk_New (Show_Caller, "Show context");
               Pack_Start (Box, Show_Caller);
               Histories.Create_New_Boolean_Key_If_Necessary
                 (Get_History (Kernel).all, "Find_Prefs_Show_Caller", False);
               Histories.Associate
                 (Get_History (Kernel).all,
                  "Find_Prefs_Show_Caller",
                  Show_Caller);

               Gtk_New
                 (Include_Overriding,
                  "Include overriding and overridden operations");
               Pack_Start (Box, Include_Overriding);
               Histories.Create_New_Boolean_Key_If_Necessary
                 (Get_History (Kernel).all,
                  "Find_Prefs_Include_Overriding",
                  False);
               Histories.Associate
                 (Get_History (Kernel).all,
                  "Find_Prefs_Include_Overriding",
                  Include_Overriding);

               Ignore := Add_Button
                 (Dialog, Gtk.Stock.Stock_Ok, Gtk_Response_OK);
               Ignore := Add_Button
                 (Dialog, Gtk.Stock.Stock_Cancel, Gtk_Response_Cancel);

               Show_All (Dialog);

               if Run (Dialog) = Gtk_Response_OK then
                  Kernel.Get_Messages_Container.Remove_Category
                    (To_String (Title), Message_Flag);

--  will be used when we have references kinds
--   if Get_Active (From_Same_File) then
--   get file(1) where entity is declared / get declaration request
--   get all entities declared in this file(1)
--   send separate requests for each entity

                  declare
                     From_File : constant GNATCOLL.VFS.Virtual_File :=
                                   (if File_Only.Get_Active
                                    then File
                                    else GNATCOLL.VFS.No_File);

                     Filter    : Result_Filter;
                     Request   : References_Request_Access :=
                                   new References_Request;

                  begin
                     for F in Dialog.Filters'Range loop
                        if Dialog.Filters (F).Get_Active then
                           Filter.Ref_Kinds.Append (All_Refs (F));
                        end if;
                     end loop;

                     Request.Kernel              := Kernel;
                     Request.Title               := Title;
                     Request.Name                := To_Unbounded_String
                       (Entity_Name_Information (Context.Context));
                     Request.Text_Document       := File;
                     Request.Line                :=
                       Line_Information (Context.Context);
                     Request.Column              :=
                       Column_Information (Context.Context);
                     Request.Include_Declaration :=
                       Get_Active (Include_Overriding);
                     Request.Show_Caller         := Get_Active (Show_Caller);
                     Request.Filter              := Filter;
                     Request.From_File           := From_File;

                     GPS.LSP_Client.Requests.Execute
                       (Lang,
                        GPS.LSP_Client.Requests.Request_Access (Request));
                  end;

                  Unchecked_Free (Dialog.Filters);
                  Destroy (Dialog);

                  return Commands.Success;
               else
                  Unchecked_Free (Dialog.Filters);
                  Destroy (Dialog);
                  return Commands.Failure;
               end if;
            end;

         else
            Kernel.Get_Messages_Container.Remove_Category
              (To_String (Title), Message_Flag);

            --  Open the Locations view if needed and put in foreground.
            --  Display an activity progress bar on since references can take
            --  some time to compute.

            GPS.Location_View.Raise_Locations_Window
              (Self             => Kernel,
               Give_Focus       => False,
               Create_If_Needed => True);
            GPS.Location_View.Set_Activity_Progress_Bar_Visibility
              (GPS.Location_View.Get_Or_Create_Location_View (Kernel),
               Visible => True);

            declare
               use type Language.Language_Access;

               Request : References_Request_Access :=
                           new References_Request;
            begin
               Request.Kernel              := Kernel;
               Request.Title               := Title;
               Request.Name                := To_Unbounded_String
                 (Entity_Name_Information (Context.Context));
               Request.Text_Document       := File;
               Request.Line                := Line_Information
                 (Context.Context);
               Request.Column              :=
                 Column_Information (Context.Context);
               Request.Include_Declaration := True;
               Request.From_File           :=
                 (if Command.Locals_Only
                  then File
                  else GNATCOLL.VFS.No_File);
               Request.Filter.Ref_Kinds    := All_Reference_Kinds;
               Request.Show_Caller         := Kernel.Get_Language_Handler.
                 Get_Language_From_File (File) = Language.Ada.Ada_Lang;

               GPS.LSP_Client.Requests.Execute
                 (Lang, GPS.LSP_Client.Requests.Request_Access (Request));
            end;

            return Commands.Success;
         end if;

      else
         --  Old implementation with XRef
         if Command.Specific then
            declare
               C : aliased GPS.Kernel.Entities.Find_Specific_Refs_Command;
            begin
               return C.Execute (Context);
            end;

         else
            declare
               C : aliased GPS.Kernel.Entities.Find_All_Refs_Command;
            begin
               C.Locals_Only := Command.Locals_Only;
               return C.Execute (Context);
            end;
         end if;
      end if;
   end Execute;

   ------------------------------
   -- Filter_Matches_Primitive --
   ------------------------------

   overriding function Filter_Matches_Primitive
     (Filter  : access Has_Entity_Name_Filter;
      Context : GPS.Kernel.Selection_Context) return Boolean
   is
      pragma Unreferenced (Filter);
   begin
      return Has_Entity_Name_Information (Context);
   end Filter_Matches_Primitive;

   -----------------------
   -- On_Result_Message --
   -----------------------

   overriding procedure On_Result_Message
     (Self   : in out References_Request;
      Result : LSP.Messages.Location_Vector)
   is
      use GNATCOLL.VFS;
      use GPS.Editors;
      use LSP.Types;
      use LSP.Messages;

      function Match (Item : LSP.Messages.Location) return Boolean;
      --  Return True when one of reference kinds of the given location match
      --  selected filter criteria.

      -----------
      -- Match --
      -----------

      function Match (Item : LSP.Messages.Location) return Boolean is
      begin
         if Item.alsKind.As_Strings.Is_Empty then
            --  Location doesn't contains any reference kinds, display it

            return True;
         end if;

         for K of Item.alsKind.As_Strings loop
            for F of Self.Filter.Ref_Kinds loop
               if K = F then
                  return True;
               end if;
            end loop;
         end loop;

         return False;
      end Match;

      Cursor           : Location_Vectors.Cursor := Result.First;
      File             : Virtual_File;
      Loc              : LSP.Messages.Location;
      Message          : GPS.Kernel.Messages.Markup.Markup_Message_Access;
      Kinds            : Ada.Strings.Unbounded.Unbounded_String;
      Aux              : LSP.Types.LSP_String_Vector;
      Buffers_To_Close : Editor_Buffer_Lists.List;
   begin
      GPS.Location_View.Set_Activity_Progress_Bar_Visibility
        (GPS.Location_View.Get_Or_Create_Location_View (Self.Kernel),
         Visible => False);

      while Location_Vectors.Has_Element (Cursor) loop
         Loc  := Location_Vectors.Element (Cursor);
         File := GPS.LSP_Client.Utilities.To_Virtual_File (Loc.uri);

         if (Self.From_File = No_File
             or else Self.From_File = File)
           and then Match (Loc)
         then
            if Self.Command = null then
               --  Construct list of reference kinds in form "[kind, kind]"
               --  if any.

               Kinds := Null_Unbounded_String;
               Aux   := Loc.alsKind.As_Strings;

               if not Aux.Is_Empty then
                  for S of Aux loop
                     if Kinds = "" then
                        Append (Kinds, '[');

                     else
                        Append (Kinds, ", ");
                     end if;

                     Append (Kinds, LSP.Types.To_UTF_8_String (S));
                  end loop;

                  Append (Kinds, "] ");
               end if;

               declare
                  Line         : constant Natural :=
                                          (if Loc.span.first.line <= 0
                                           then 1
                                           else Integer
                                             (Loc.span.first.line) + 1);
                  Start_Column : constant Basic_Types.Visible_Column_Type :=
                                          UTF_16_Offset_To_Visible_Column
                                     (Loc.span.first.character);
                  End_Column   : constant Basic_Types.Visible_Column_Type :=
                                   UTF_16_Offset_To_Visible_Column
                                     (Loc.span.last.character);
                  Buffer       : Editor_Buffer_Holders.Holder :=
                                          Editor_Buffer_Holders.To_Holder
                                            (Self.Kernel.Get_Buffer_Factory.Get
                                               (File            => File,
                                                Force           => False,
                                                Open_Buffer     => False,
                                                Open_View       => False,
                                                Focus           => False,
                                                Only_If_Focused => False));
               begin

                  --  If no buffer was opened for the given file, open a new
                  --  one.
                  --  Append it to the list of buffers that we should close
                  --  when exiting the functions.

                  if Buffer.Element = Nil_Editor_Buffer then
                     Buffer := Editor_Buffer_Holders.To_Holder
                       (Self.Kernel.Get_Buffer_Factory.Get
                          (File            => File,
                           Force           => False,
                           Open_Buffer     => True,
                           Open_View       => False,
                           Focus           => False,
                           Only_If_Focused => False));
                     Buffers_To_Close.Append (Buffer);
                  end if;

                  declare
                     Start_Loc  : constant GPS.Editors.Editor_Location'Class :=
                                    Buffer.Element.New_Location_At_Line
                                      (Line);
                     End_Loc    : constant GPS.Editors.Editor_Location'Class :=
                                       Start_Loc.End_Of_Line;
                     Whole_Line : constant String := Buffer.Element.Get_Chars
                       (From => Start_Loc,
                        To   => End_Loc);
                     Start      : Natural := Whole_Line'First;
                     Last       : Natural := Whole_Line'Last;
                  begin

                     --  We got the whole line containing the reference: strip
                     --  the blankspaces at the beginning/end of the line.

                     Skip_Blanks (Whole_Line, Index => Start);
                     Skip_Blanks_Backward (Whole_Line, Index => Last);

                     --  Get the text after and before the reference and
                     --  concatenate it with the reference itself surrounded by
                     --  bold markup.

                     declare
                        Before_Idx  : constant Natural :=
                                        (Whole_Line'First - 1)
                                        + UTF8_Utils.Column_To_Index
                                          (Whole_Line,
                                           Character_Offset_Type
                                             (Start_Column) - 1);
                        After_Idx   : constant Natural :=
                                        (Whole_Line'First - 1)
                                        + UTF8_Utils.Column_To_Index
                                          (Whole_Line,
                                           Character_Offset_Type
                                             (End_Column));
                        Before_Text : constant String :=
                                        Whole_Line
                                          (Start .. Before_Idx);
                        After_Text  : constant String :=
                                        Whole_Line
                                          (After_Idx .. Last);
                        Name_Text   : constant String :=
                                        Whole_Line
                                          (Before_Idx + 1 .. After_Idx - 1);
                        Msg_Text    : constant String :=
                                        Escape_Text (Before_Text)
                                      & "<b>"
                                        & Escape_Text (Name_Text)
                                        & "</b>"
                                        & Escape_Text (After_Text);
                     begin
                        Message :=
                          GPS.Kernel.Messages.Markup.Create_Markup_Message
                            (Container  => Self.Kernel.Get_Messages_Container,
                             Category   => To_String (Self.Title),
                             File       => File,
                             Line       => Line,
                             Column     => Start_Column,
                             Text       => To_String (Kinds) & Msg_Text,

                             --  will be used when we have references kinds
                             --  & if Self.Show_Caller and then Get_Caller
                             --  (Ref) /= No_Root_Entity then
                             --    Add "called by" information to the response

                             Importance => Unspecified,
                             Flags      => Message_Flag);
                        GPS.Kernel.Messages.Set_Highlighting
                          (Self   => Message,
                           Style  => Search_Results_Style,
                           --  The number of characters to highlight is the
                           --  number of decoded UTF-8 characters
                           Length => Highlight_Length
                             (UTF8_Utils.UTF8_Length (To_String (Self.Name))));
                     end;
                  end;
               end;

            else
               --  fill command list to return as a result via python API
               Self.Command.Locations.Append (Loc);
            end if;
         end if;
         Location_Vectors.Next (Cursor);
      end loop;

      --  Close all the buffers that were not opened at the beginning.
      --  This allows to save memory.

      for Buffer of Buffers_To_Close loop
         Buffer.Element.Close;
      end loop;
   end On_Result_Message;

   --------------
   -- Finalize --
   --------------

   overriding procedure Finalize (Self : in out References_Request) is
      Locations_View : constant GPS.Location_View.Location_View_Access :=
                         GPS.Location_View.Get_Or_Create_Location_View
                           (Self.Kernel,
                            Allow_Creation => False);
   begin
      if Locations_View /= null then
         GPS.Location_View.Set_Activity_Progress_Bar_Visibility
           (Locations_View,
            Visible => False);
      end if;

      GPS.LSP_Client.Requests.References.Finalize
        (GPS.LSP_Client.Requests.References.Abstract_References_Request
           (Self));
   end Finalize;

   ------------------------
   -- Select_All_Filters --
   ------------------------

   procedure Select_All_Filters (Dialog : access Gtk_Widget_Record'Class) is
      D : constant References_Filter_Dialog :=
        References_Filter_Dialog (Dialog);
   begin
      for F in D.Filters'Range loop
         Set_Active (D.Filters (F), True);
      end loop;
   end Select_All_Filters;

   --------------------------
   -- Unselect_All_Filters --
   --------------------------

   procedure Unselect_All_Filters (Dialog : access Gtk_Widget_Record'Class) is
      D : constant References_Filter_Dialog :=
        References_Filter_Dialog (Dialog);
   begin
      for F in D.Filters'Range loop
         Set_Active (D.Filters (F), False);
      end loop;
   end Unselect_All_Filters;

   -------------------
   -- Find_All_Refs --
   -------------------

   procedure Find_All_Refs
     (Kernel   : Kernel_Handle;
      File     : GNATCOLL.VFS.Virtual_File;
      Line     : Integer;
      Column   : Basic_Types.Visible_Column_Type;
      Name     : String;
      Implicit : Boolean;
      In_File  : GNATCOLL.VFS.Virtual_File;
      Data     : GNATCOLL.Scripts.Callback_Data_Access)
   is
      Lang  : Standard.Language.Language_Access;
      Title : Unbounded_String;

   begin
      Lang := Kernel.Get_Language_Handler.Get_Language_From_File (File);

      if GPS.LSP_Module.LSP_Is_Enabled (Lang) then
         --  Implicit is used for Is_Read_Or_Write_Or_Implicit_Reference
         Title := To_Unbounded_String
           (All_Refs_Category
              (Entity             => Name,
               Line               => Line,
               Local_Only         => False,
               Local_File         => File,
               All_From_Same_File => False));

         Kernel.Get_Messages_Container.Remove_Category
           (To_String (Title), Message_Flag);

         declare
            use GNATCOLL.Scripts;
            use type Language.Language_Access;

            Command : constant Ref_Command_Access :=
              (if Data = null
               then null
               else new References_Command);

            Request : References_Request_Access :=
              new References_Request;
         begin
            Request.Kernel              := Kernel;
            Request.Title               := Title;
            Request.Name                := To_Unbounded_String (Name);
            Request.Text_Document       := File;
            Request.Line                := Line;
            Request.Column              := Column;
            Request.Include_Declaration := True;
            Request.From_File           := GNATCOLL.VFS.No_File;
            Request.Filter.Ref_Kinds    := All_Reference_Kinds;
            Request.Show_Caller         := Kernel.Get_Language_Handler.
              Get_Language_From_File (File) = Language.Ada.Ada_Lang;
            Request.Command             := Command;

            GPS.LSP_Client.Requests.Execute
              (Lang, GPS.LSP_Client.Requests.Request_Access (Request));

            if Data /= null then
               Data.Set_Return_Value
                 (GPS.Scripts.Commands.Get_Instance
                    (GPS.Scripts.Commands.Create_Wrapper (Command),
                     Data.Get_Script,
                     Class_To_Create => References_Command_Class_Name));
            end if;
         end;

      else
         --  Use old implementation Src_Editor_Module -> Entity -> Xref

         Src_Editor_Module.Shell.Find_All_Refs
           (Kernel, File, Line, Column, Name, Implicit, In_File, Data);
      end if;
   end Find_All_Refs;

   ----------------
   -- Get_Result --
   ----------------

   overriding procedure Get_Result
     (Self : not null access References_Command;
      Data : in out GNATCOLL.Scripts.Callback_Data'Class)
   is
      use GNATCOLL.Scripts;
      use GPS.Kernel.Scripts;

      Inst : Class_Instance;
   begin
      Set_Return_Value_As_List (Data);

      for Loc of Self.Locations loop
         Inst := Create_File_Location
           (Script => Get_Script (Data),
            File   => Create_File
              (Script => Get_Script (Data),
               File   => GPS.LSP_Client.Utilities.To_Virtual_File (Loc.uri)),
            Line   => Integer (Loc.span.first.line) + 1,
            Column => GPS.LSP_Client.Utilities.UTF_16_Offset_To_Visible_Column
              (Loc.span.first.character));

         Set_Return_Value (Data, Inst);
      end loop;
   end Get_Result;

   --------------
   -- Register --
   --------------

   procedure Register (Kernel : Kernel_Handle) is
      Has_Entity_Name : constant Action_Filter := new Has_Entity_Name_Filter;
   begin
      Src_Editor_Module.Shell.Find_All_Refs_Handler := Find_All_Refs'Access;

      Register_Action
        (Kernel, "find all references",
         Command     => new Find_Refs_Command (False, False),
         Description =>
           "List all references to the selected entity"
             & " in the Locations window",
         Filter => Has_Entity_Name);

      GPS.Kernel.Modules.UI.Register_Contextual_Menu
        (Kernel,
         Name   => "Find All References",
         Action => "find all references",
         Group  => GPS.Kernel.Modules.UI.Navigation_Contextual_Group);

      Register_Action
        (Kernel, "find all local references",
         Command     => new Find_Refs_Command (True, False),
         Description =>
           "List all references in the selected file to the selected entity"
           & " in the Locations window",
         Filter => Has_Entity_Name);

      Register_Action
        (Kernel, "find references...",
         Command     => new Find_Refs_Command (False, True),
         Description =>
           "List all references to the selected entity"
           & " in the Locations window, with extra filters",
         Filter => Has_Entity_Name);
   end Register;

end GPS.LSP_Client.References;
