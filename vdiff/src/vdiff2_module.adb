-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                        Copyright (C) 2001-2003                    --
--                            ACT-Europe                             --
--                                                                   --
-- GPS is free  software;  you can redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this program; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with Glib;                      use Glib;
with Glib.Object;               use Glib.Object;
with Glib.Values;               use Glib.Values;

with Gtkada.File_Selector;      use Gtkada.File_Selector;
with Gtkada.Dialogs;            use Gtkada.Dialogs;
with Gtk.Toolbar;               use Gtk.Toolbar;
with Gtk.Window;                use Gtk.Window;
with Gdk.Pixmap;                use Gdk.Pixmap;
with Gdk.Bitmap;                use Gdk.Bitmap;
with Pixmaps_Vdiff2;            use Pixmaps_Vdiff2;
--   with Pixmaps_IDE;               use Pixmaps_IDE;
with Glide_Kernel;              use Glide_Kernel;
with Glide_Kernel.Modules;      use Glide_Kernel.Modules;
with Glide_Kernel.Preferences;  use Glide_Kernel.Preferences;
with Glide_Intl;                use Glide_Intl;
with Basic_Types;               use Basic_Types;
with Diff_Utils2;               use Diff_Utils2;

with Vdiff2_Utils;              use Vdiff2_Utils;
with Vdiff2_Command;            use Vdiff2_Command;
with OS_Utils;                  use OS_Utils;

with GNAT.Directory_Operations; use GNAT.Directory_Operations;
with Ada.Exceptions;            use Ada.Exceptions;
with Traces;                    use Traces;

with GNAT.OS_Lib;               use GNAT.OS_Lib;
with Gdk.Bitmap;                use Gdk.Bitmap;
with Gtk.Image;                 use Gtk.Image;
with Gdk.Color;                 use Gdk.Color;
with Commands;                  use Commands;

with Gtk.Handlers;              use Gtk.Handlers;


package body Vdiff2_Module is
   use Diff_Head_List;
   use Diff_Chunk_List;

   Me : constant Debug_Handle := Create (Vdiff_Module_Name);

   function Mime_Action
     (Kernel    : access Kernel_Handle_Record'Class;
      Mime_Type : String;
      Data      : GValue_Array;
      Mode      : Mime_Mode := Read_Write) return Boolean;
   --  Process, if possible, the data sent by the kernel

   procedure On_Compare_Three_Files
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle);
   --  Callback for Tools->VDiff->Compare Two Files...

   procedure On_Compare_Two_Files
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle);
   --  Callback for Tools->VDiff->Compare Tree Files...

   procedure On_Merge_Three_Files
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle);
   --  Callback for Tools->VDiff->Merge Two Files...

   procedure On_Merge_Two_Files
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle);
   --  Callback for Tools->VDiff->Merge Tree Files...

   procedure File_Closed_Cb
     (Widget  : access Glib.Object.GObject_Record'Class;
      Args    : GValues;
      Kernel  : Kernel_Handle);
   --  Callback for the "file_closed" signal.

   procedure On_Preferences_Changed
     (Kernel : access GObject_Record'Class; K : Kernel_Handle);
   --  Called when the preferences have changed

   No_Handler : constant Handler_Id := (Null_Signal_Id, null);

   type VDiff2_Module_Record is new Module_ID_Record with record
      Kernel              : Kernel_Handle;
      Is_Active           : Boolean := False;
      Number_active       : Natural := 0;
      List_Diff           : Diff_Head_List_Access;
      Command_Prev        : Diff_Command_Access;
      Command_Next        : Diff_Command_Access;
      Command_First       : Diff_Command_Access;
      Command_Last        : Diff_Command_Access;
      Command_Close       : Diff_Command_Access;
      Command_Reload      : Diff_Command_Access;
      Command_Unhighlight : Diff_Command_Access;
      File_Closed_Id      : Handler_Id := No_Handler;
   end record;
   type VDiff2_Module is access all VDiff2_Module_Record'Class;

   procedure Destroy (Id : in out VDiff2_Module_Record);

   ---------------------------
   -- On_Compare_Tree_Files --
   ---------------------------

   procedure On_Compare_Three_Files
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle)
   is
      Id     : constant VDiff2_Module := VDiff2_Module (Vdiff_Module_ID);
      Item   : Diff_Head;
      Result : Diff_List;
      File1  : constant String :=
        Select_File
          (Title             => -"Select Common Ancestor",
           Parent            => Get_Main_Window (Kernel),
           Use_Native_Dialog => Get_Pref (Kernel, Use_Native_Dialogs),
           Kind              => Unspecified,
           History           => Get_History (Kernel));
      Button : Message_Dialog_Buttons;
      pragma Unreferenced (Widget, Button);

   begin
      if File1 = "" then
         return;
      end if;
      Change_Dir (Dir_Name (File1));
      declare
         File2 : constant String :=
           Select_File
             (Title             => -"Select First Changes",
              Base_Directory    => "",
              Parent            => Get_Main_Window (Kernel),
              Use_Native_Dialog => Get_Pref (Kernel, Use_Native_Dialogs),
              Kind              => Unspecified,
              History           => Get_History (Kernel));
         Dummy : Command_Return_Type;
         pragma Unreferenced (Dummy);
      begin
         if File2 = "" then
            return;
         end if;
         Change_Dir (Dir_Name (File2));
         declare
            File3 : constant String :=
              Select_File
                (Title             => -"Select Second Changes",
                 Base_Directory    => "",
                 Parent            => Get_Main_Window (Kernel),
                 Use_Native_Dialog => Get_Pref (Kernel, Use_Native_Dialogs),
                 Kind              => Unspecified,
                 History           => Get_History (Kernel));

         begin
            if File3 = "" then
               return;
            end if;

            Result := Diff3 (Kernel, File1, File2, File3);

            if Result = Diff_Chunk_List.Null_List then
               Button := Message_Dialog
                 (Msg         => -"No differences found.",
                  Buttons     => Button_OK,
                  Parent      => Get_Main_Window (Kernel));
               return;
            end if;
            Item := (List => Result,
                     File1 => new String'(File1),
                     File2 => new String'(File2),
                     File3 => new String'(File3),
                     Current_Node => First (Result),
                     Ref_File => 2);
            Show_Differences3 (Kernel, Item);
            Append (Id.List_Diff.all, Item);
            Dummy := Execute (Id.Command_First);
            --  Free (Result);
         end;
      end;
   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Compare_Three_Files;

   --------------------------
   -- On_Compare_Two_Files --
   --------------------------

   procedure On_Compare_Two_Files
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle)
   is
      Id     : constant VDiff2_Module := VDiff2_Module (Vdiff_Module_ID);
      Item   : Diff_Head;
      Result : Diff_List;
      File1  : constant String :=
        Select_File
          (Title             => -"Select First File",
           Base_Directory    => "",
           Parent            => Get_Main_Window (Kernel),
           Use_Native_Dialog => Get_Pref (Kernel, Use_Native_Dialogs),
           Kind              => Unspecified,
           History           => Get_History (Kernel));
      Button : Message_Dialog_Buttons;
      pragma Unreferenced (Widget, Button);

   begin
      if File1 = "" then
         return;
      end if;
      Change_Dir (Dir_Name (File1));
      declare
         File2 : constant String :=
           Select_File
             (Title             => -"Select Second File",
              Base_Directory    => "",
              Parent            => Get_Main_Window (Kernel),
              Use_Native_Dialog => Get_Pref (Kernel, Use_Native_Dialogs),
              Kind              => Unspecified,
              History           => Get_History (Kernel));
         Dummy : Command_Return_Type;
         pragma Unreferenced (Dummy);

      begin
         if File2 = "" then
            return;
         end if;

         Result := Diff (Kernel, File1, File2);

         if Result = Diff_Chunk_List.Null_List then
            Button := Message_Dialog
              (Msg         => -"No differences found.",
               Buttons     => Button_OK,
               Parent      => Get_Main_Window (Kernel));
            return;
         end if;

         Item := (List => Result,
                  File1 => new String'(File1),
                  File2 => new String'(File2),
                  File3 => null,
                  Current_Node => First (Result),
                  Ref_File => 2);
         Show_Differences3 (Kernel, Item);
         Append (Id.List_Diff.all, Item);
         Dummy := Execute (Id.Command_First);
      end;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Compare_Two_Files;

   -------------------------
   -- On_Merge_Tree_Files --
   -------------------------

   procedure On_Merge_Three_Files
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle)
   is
      Id     : constant VDiff2_Module := VDiff2_Module (Vdiff_Module_ID);
      Item   : Diff_Head;
      Result : Diff_List;
      File1  : constant String :=
        Select_File
          (Title             => -"Select Common Ancestor",
           Base_Directory    => "",
           Parent            => Get_Main_Window (Kernel),
           Use_Native_Dialog => Get_Pref (Kernel, Use_Native_Dialogs),
           Kind              => Unspecified,
           History           => Get_History (Kernel));
      Button : Message_Dialog_Buttons;
      pragma Unreferenced (Widget, Button);

   begin
      if File1 = "" then
         return;
      end if;
      Change_Dir (Dir_Name (File1));
      declare
         File2 : constant String :=
           Select_File
             (Title             => -"Select First Changes",
              Base_Directory    => "",
              Parent            => Get_Main_Window (Kernel),
              Use_Native_Dialog => Get_Pref (Kernel, Use_Native_Dialogs),
              Kind              => Unspecified,
              History           => Get_History (Kernel));

      begin
         if File2 = "" then
            return;
         end if;
         Change_Dir (Dir_Name (File2));
         declare
            File3 : constant String :=
              Select_File
                (Title             => -"Select Second Changes",
                 Base_Directory    => "",
                 Parent            => Get_Main_Window (Kernel),
                 Use_Native_Dialog => Get_Pref (Kernel, Use_Native_Dialogs),
                 Kind              => Unspecified,
                 History           => Get_History (Kernel));
            Dummy : Command_Return_Type;
            pragma Unreferenced (Dummy);

         begin
            if File3 = "" then
               return;
            end if;
            Change_Dir (Dir_Name (File3));
            Result := Diff3 (Kernel, File1, File2, File3);

            if Result = Diff_Chunk_List.Null_List then
               Button := Message_Dialog
                 (Msg         => -"No differences found.",
                  Buttons     => Button_OK,
                  Parent      => Get_Main_Window (Kernel));
               return;
            end if;

            Item := (List => Result,
                     File1 => new String'(File1),
                     File2 => new String'(File2),
                     File3 => new String'(File3),
                     Current_Node => First (Result),
                     Ref_File => 2);
            Show_Differences3 (Kernel, Item);
            Append (Id.List_Diff.all, Item);
            Dummy := Execute (Id.Command_First);

            declare
               Merge     : constant String :=
                 Select_File
                   (Title             => -"Select Merge File",
                    Base_Directory    => "",
                    Parent            => Get_Main_Window (Kernel),
                    Use_Native_Dialog => Get_Pref (Kernel, Use_Native_Dialogs),
                    Kind              => Unspecified,
                    History           => Get_History (Kernel));
               Args_edit : Argument_List := (1 => new String'(Merge));

            begin
               if Merge /= "" then
                  Show_Merge (Kernel, Merge, Item);
               end if;

               Free (Args_edit);
            end;
         end;
      end;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Merge_Three_Files;

   ------------------------
   -- On_Merge_Two_Files --
   ------------------------

   procedure On_Merge_Two_Files
     (Widget : access GObject_Record'Class; Kernel : Kernel_Handle)
   is
      Id     : constant VDiff2_Module := VDiff2_Module (Vdiff_Module_ID);
      Item   : Diff_Head;
      Result : Diff_List;
      File1  : constant String :=
        Select_File
          (Title             => -"Select First File",
           Parent            => Get_Main_Window (Kernel),
           Use_Native_Dialog => Get_Pref (Kernel, Use_Native_Dialogs),
           Kind              => Unspecified,
           History           => Get_History (Kernel));
      Button : Message_Dialog_Buttons;
      pragma Unreferenced (Widget, Button);

   begin
      if File1 = "" then
         return;
      end if;
      Change_Dir (Dir_Name (File1));
      declare
         File2 : constant String :=
           Select_File
             (Title             => -"Select Second File",
              Base_Directory    => "",
              Parent            => Get_Main_Window (Kernel),
              Use_Native_Dialog => Get_Pref (Kernel, Use_Native_Dialogs),
              Kind              => Unspecified,
              History           => Get_History (Kernel));
         Dummy : Command_Return_Type;
         pragma Unreferenced (Dummy);

      begin
         if File2 = "" then
            return;
         end if;
         Change_Dir (Dir_Name (File2));
         Result := Diff (Kernel, File1, File2);

         if Result = Diff_Chunk_List.Null_List then
            Button := Message_Dialog
              (Msg         => -"No differences found.",
               Buttons     => Button_OK,
               Parent      => Get_Main_Window (Kernel));
            return;
         end if;

         Item := (List => Result,
                  File1 => new String'(File1),
                  File2 => new String'(File2),
                  File3 => null,
                  Current_Node => First (Result),
                  Ref_File => 2);
         Show_Differences3 (Kernel, Item);
         Append (Id.List_Diff.all, Item);
         Dummy := Execute (Id.Command_First);

         declare
            Merge     : constant String :=
              Select_File
                (Title             => -"Select Merge File",
                 Base_Directory    => "",
                 Parent            => Get_Main_Window (Kernel),
                 Use_Native_Dialog => Get_Pref (Kernel, Use_Native_Dialogs),
                 Kind              => Unspecified,
                 History           => Get_History (Kernel));
            Args_edit : Argument_List := (1 => new String'(Merge));

         begin
            if Merge /= "" then
               Show_Merge (Kernel, Merge, Item);
            end if;

            Free (Args_edit);
         end;
      end;

   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Merge_Two_Files;
   -----------------
   -- Mime_Action --
   -----------------

   function Mime_Action
     (Kernel    : access Kernel_Handle_Record'Class;
      Mime_Type : String;
      Data      : GValue_Array;
      Mode      : Mime_Mode := Read_Write) return Boolean
   is
      Id      : constant VDiff2_Module := VDiff2_Module (Vdiff_Module_ID);
      Item    : Diff_Head;
      Result  : Diff_List;
      Success : Boolean;
      Button  : Message_Dialog_Buttons;
      Dummy : Command_Return_Type;
      pragma Unreferenced (Mode, Button, Dummy);

   begin

      if Mime_Type = Mime_Diff_File then
         declare
            Orig_File : constant String := Get_String (Data (Data'First));
            New_File  : constant String := Get_String (Data (Data'First + 1));
            Diff_File : constant String := Get_String (Data (Data'First + 2));

         begin
            if Orig_File = "" then
               if New_File = "" then
                  return False;
               end if;

               declare
                  Base     : constant String := Base_Name (New_File);
                  Ref_File : constant String := Get_Tmp_Dir & Base & "$ref";

               begin
                  Result := Diff
                    (Kernel, Ref_File, New_File, Diff_File, Revert => True);

                  if Result = Diff_Chunk_List.Null_List then
                     Button := Message_Dialog
                       (Msg         => -"No differences found.",
                        Buttons     => Button_OK,
                        Parent      => Get_Main_Window (Kernel));
                     return False;
                  end if;

                  Item :=
                    (List => Result,
                     File1 => new String'(Ref_File),
                     File2 => new String'(New_File),
                     File3 => null,
                     Current_Node => First (Result),
                     Ref_File => 2);
                  Append (Id.List_Diff.all, Item);
                  Show_Differences3 (Kernel, Item);
                  Delete_File (Ref_File, Success);
               end;

            elsif New_File = "" then
               if Orig_File = "" then
                  return False;
               end if;

               declare
                  Base     : constant String := Base_Name (Orig_File);
                  Ref_File : constant String := Get_Tmp_Dir & Base & "$ref";

               begin
                  Result := Diff (Kernel, Orig_File, Ref_File, Diff_File);

                  if Result = Diff_Chunk_List.Null_List then
                     Button := Message_Dialog
                       (Msg         => -"No differences found.",
                        Buttons     => Button_OK,
                        Parent      => Get_Main_Window (Kernel));
                     return False;
                  end if;
                  Item := (List => Result,
                                 File1 => new String'(Orig_File),
                                 File2 => new String'(Ref_File),
                                 File3 => null,
                                 Current_Node => First (Result),
                                 Ref_File => 2);
                  Append (Id.List_Diff.all, Item);
                  Show_Differences3 (Kernel, Item);
                  Delete_File (Ref_File, Success);
               end;

            else
               --  All arguments are specified

               Result := Diff (Kernel, Orig_File, New_File, Diff_File);

               if Result = Diff_Chunk_List.Null_List then
                  Button := Message_Dialog
                    (Msg         => -"No differences found.",
                     Buttons     => Button_OK,
                     Parent      => Get_Main_Window (Kernel));
                  return False;
               end if;

               Item :=
                 (List => Result,
                  File1 => new String'(Orig_File),
                  File2 => new String'(New_File),
                  File3 => null,
                  Current_Node => First (Result),
                  Ref_File => 2);
               Append (Id.List_Diff.all, Item);
               Show_Differences3 (Kernel, Item);
            end if;

            Dummy := Execute (Id.Command_First);
            return True;
         end;
      end if;

      return False;
   end Mime_Action;

   ---------------------
   -- Register_Module --
   ---------------------

   procedure Register_Module
     (Kernel : access Glide_Kernel.Kernel_Handle_Record'Class)
   is
      Toolbar      : constant Gtk_Toolbar := Get_Toolbar (Kernel);
      Window       : constant Gtk_Window  := Get_Main_Window (Kernel);
      Tools        : constant String := '/' & (-"Tools") & '/'
        & (-"Visual Diff") & '/';
      Image   : Gtk_Image;
      Mask    : Gdk_Bitmap;
      PixMap  : Gdk_Pixmap;

   begin
      Vdiff_Module_ID := new VDiff2_Module_Record;
      VDiff2_Module (Vdiff_Module_ID).Kernel := Kernel_Handle (Kernel);
      VDiff2_Module (Vdiff_Module_ID).List_Diff :=
        new Diff_Head_List.List;
      VDiff2_Module (Vdiff_Module_ID).File_Closed_Id :=
        Kernel_Callback.Connect
          (Kernel,
           File_Closed_Signal,
           File_Closed_Cb'Access,
           Kernel_Handle (Kernel));

      Create (VDiff2_Module (Vdiff_Module_ID).Command_Last,
                VDiff2_Module (Vdiff_Module_ID).Kernel,
                VDiff2_Module (Vdiff_Module_ID).List_Diff,
                Last_Difference'Access);

      Create (VDiff2_Module (Vdiff_Module_ID).Command_First,
                VDiff2_Module (Vdiff_Module_ID).Kernel,
                VDiff2_Module (Vdiff_Module_ID).List_Diff,
                First_Difference'Access);

      Create (VDiff2_Module (Vdiff_Module_ID).Command_Next,
                VDiff2_Module (Vdiff_Module_ID).Kernel,
                VDiff2_Module (Vdiff_Module_ID).List_Diff,
                Next_Difference'Access);

      Create (VDiff2_Module (Vdiff_Module_ID).Command_Prev,
                VDiff2_Module (Vdiff_Module_ID).Kernel,
                VDiff2_Module (Vdiff_Module_ID).List_Diff,
                Prev_Difference'Access);

      Create (VDiff2_Module (Vdiff_Module_ID).Command_Close,
                VDiff2_Module (Vdiff_Module_ID).Kernel,
                VDiff2_Module (Vdiff_Module_ID).List_Diff,
                Close_Difference'Access);

      Create (VDiff2_Module (Vdiff_Module_ID).Command_Reload,
                VDiff2_Module (Vdiff_Module_ID).Kernel,
                VDiff2_Module (Vdiff_Module_ID).List_Diff,
                Reload_Difference'Access);

      Create (VDiff2_Module (Vdiff_Module_ID).Command_Unhighlight,
                VDiff2_Module (Vdiff_Module_ID).Kernel,
                VDiff2_Module (Vdiff_Module_ID).List_Diff,
                Unhighlight_Difference'Access);

      Register_Module
        (Module       => Vdiff_Module_ID,
         Kernel       => Kernel,
         Module_Name  => Vdiff_Module_Name,
         Priority     => Default_Priority,
         Mime_Handler => Mime_Action'Access);

      Diff3_Cmd := Param_Spec_String
      (Gnew_String
       (Name  => "Diff-Utils-Diff3",
        Nick  => -"Diff3 command",
        Blurb => -("Command used to compute differences between three files."
                         & " Arguments can also be specified"),
            Default => "diff3"));
      Register_Property
        (Kernel, Param_Spec (Diff3_Cmd), -"Visual diff");

      Diff_Default_Color := Param_Spec_Color
        (Gnew_Color
           (Name     =>  "Diff-Default-Color",
            Nick     => -"Default Color",
            Blurb    => -"Color used for highlighting in Visual Diff2",
            Default  => "#AAAAFF"));
      Register_Property
        (Kernel, Param_Spec (Diff_Default_Color), -"Visual diff");

      Diff_Old_Color := Param_Spec_Color
        (Gnew_Color
           (Name     =>  "Diff-Old-Color",
            Nick     => -"Old Color",
            Blurb    => -"Color used for highlighting in Visual Diff2",
            Default  => "#C1C1C1"));
      Register_Property
        (Kernel, Param_Spec (Diff_Old_Color), -"Visual diff");

      Diff_Append_Color := Param_Spec_Color
        (Gnew_Color
           (Name     =>  "Diff-Append-Color",
            Nick     => -"Append Color",
            Blurb    => -"Color used for highlighting in Visual Diff2",
            Default  => "#88EEAA"));
      Register_Property
        (Kernel, Param_Spec (Diff_Append_Color), -"Visual diff");

      Diff_Remove_Color := Param_Spec_Color
        (Gnew_Color
           (Name     =>  "Diff-Remove-Color",
            Nick     => -"Remove Color",
            Blurb    => -"Color used for highlighting in Visual Diff2",
            Default  => "#FFA0A0"));
      Register_Property
        (Kernel, Param_Spec (Diff_Remove_Color), -"Visual diff");

      Diff_Change_Color := Param_Spec_Color
        (Gnew_Color
           (Name     =>  "Diff-Change-Color",
            Nick     => -"Change Color",
            Blurb    => -"Color used for highlighting in Visual Diff2",
            Default  => "#ECECAA"));
      Register_Property
        (Kernel, Param_Spec (Diff_Change_Color), -"Visual diff");

      Kernel_Callback.Connect
        (Kernel, Preferences_Changed_Signal,
         Kernel_Callback.To_Marshaller (On_Preferences_Changed'Access),
         Kernel_Handle (Kernel));

      Register_Menu
        (Kernel, Tools, -"Compare Two Files...", "",
         On_Compare_Two_Files'Access);
      Register_Menu
        (Kernel, Tools, -"Compare Three Files...", "",
         On_Compare_Three_Files'Access);
      Register_Menu
        (Kernel, Tools, -"Merge Two Files...", "",
         On_Merge_Two_Files'Access);
      Register_Menu
        (Kernel, Tools, -"Merge Three Files...", "",
         On_Merge_Three_Files'Access);
      Append_Space (Toolbar);

      Create_From_Xpm_D
        (PixMap, Get_Window (Window), Mask, Null_Color, up_diff_xpm);
      Gtk_New (Image, PixMap, Mask);
      Register_Button
        (Kernel, -"Go to prev mark",
         Command_Access (VDiff2_Module (Vdiff_Module_ID).Command_Prev),
         Image);

      Create_From_Xpm_D
        (PixMap, Get_Window (Window), Mask, Null_Color, down_diff_xpm);
      Gtk_New (Image, PixMap, Mask);
      Register_Button (Kernel, -"Go to next mark",
                         Command_Access
                           (VDiff2_Module (Vdiff_Module_ID).Command_Next),
                         Image);

      Create_From_Xpm_D
        (PixMap, Get_Window (Window), Mask, Null_Color, last_diff_xpm);
      Gtk_New (Image, PixMap, Mask);
      Register_Button (Kernel, -"Go to the last difference",
                         Command_Access
                           (VDiff2_Module (Vdiff_Module_ID).Command_Last),
                         Image);
      Create_From_Xpm_D
        (PixMap, Get_Window (Window), Mask, Null_Color, first_diff_xpm);
      Gtk_New (Image, PixMap, Mask);
      Register_Button (Kernel, -"Go to the First difference",
                         Command_Access
                           (VDiff2_Module (Vdiff_Module_ID).Command_First),
                         Image);

      Create_From_Xpm_D
        (PixMap, Get_Window (Window), Mask, Null_Color, reload_diff_xpm);
      Gtk_New (Image, PixMap, Mask);
      Register_Button (Kernel, -"Recalculate Differences",
                         Command_Access
                           (VDiff2_Module (Vdiff_Module_ID).Command_Reload),
                         Image);
      Create_From_Xpm_D
        (PixMap, Get_Window (Window), Mask, Null_Color, close_diff_xpm);
      Gtk_New (Image, PixMap, Mask);
      Register_Button (Kernel, -"Close difference",
                         Command_Access
                           (VDiff2_Module (Vdiff_Module_ID).Command_Close),
                         Image);

      Create_From_Xpm_D
        (PixMap, Get_Window (Window), Mask, Null_Color, unhighlight_diff_xpm);
      Gtk_New (Image, PixMap, Mask);
      Register_Button (Kernel, -"remove highlighting",
                         Command_Access
                         (VDiff2_Module (Vdiff_Module_ID).Command_Unhighlight),
                         Image);
   end Register_Module;


   -------------
   -- Destroy --
   -------------

   procedure Destroy (Id : in out VDiff2_Module_Record)
   is
   begin
      Free_List (Id.List_Diff.all);
      Free (Id.List_Diff.all);
      Free (Root_Command (Id.Command_Prev.all));
      Free (Root_Command (Id.Command_Next.all));
      Free (Root_Command (Id.Command_First.all));
      Free (Root_Command (Id.Command_Last.all));
      Free (Root_Command (Id.Command_Close.all));
      Free (Root_Command (Id.Command_Reload.all));
      Free (Root_Command (Id.Command_Unhighlight.all));
   end Destroy;

   --------------------
   -- File_Closed_Cb --
   --------------------

   procedure File_Closed_Cb
     (Widget  : access Glib.Object.GObject_Record'Class;
      Args    : GValues;
      Kernel  : Kernel_Handle)
   is
      Diff     : Diff_Head_Access := new Diff_Head;
      File     : constant String := Get_String (Nth (Args, 1));
      CurrNode : Diff_Head_List.List_Node :=
        First (VDiff2_Module (Vdiff_Module_ID).List_Diff.all);
      pragma Unreferenced (Widget);

   begin
      while CurrNode /= Diff_Head_List.Null_Node
      loop
         Diff.all := Data (CurrNode);
         exit when ((Diff.File1 /= null and then Diff.File1.all = File)
                       or else
                         (Diff.File2 /= null and then Diff.File2.all = File)
                       or else
                         (Diff.File3 /= null and then Diff.File3.all = File));
         CurrNode := Next (CurrNode);
      end loop;

      if CurrNode /= Diff_Head_List.Null_Node then
         Hide_Differences (Kernel, Diff.all);
         Remove_Nodes (VDiff2_Module (Vdiff_Module_ID).List_Diff.all,
                          Prev (VDiff2_Module (Vdiff_Module_ID).List_Diff.all,
                             CurrNode),
                          CurrNode);
      end if;
      Free_All (Diff.all);
      Free (Diff);
   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end File_Closed_Cb;

   procedure On_Preferences_Changed
     (Kernel : access GObject_Record'Class; K : Kernel_Handle) is
      pragma Unreferenced (Kernel);
   begin
      Register_Highlighting (K);
   exception
      when E : others =>
         Trace (Me, "Unexpected exception: " & Exception_Information (E));
   end On_Preferences_Changed;

end Vdiff2_Module;








