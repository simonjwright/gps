-----------------------------------------------------------------------
--                          G L I D E  I I                           --
--                                                                   --
--                        Copyright (C) 2001                         --
--                            ACT-Europe                             --
--                                                                   --
-- GLIDE is free software; you can redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this library; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with Gtk.Main; use Gtk.Main;
with String_Utils; use String_Utils;
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Characters.Handling; use Ada.Characters.Handling;

with Gtkada.Dialogs; use Gtkada.Dialogs;
with String_Utils;   use String_Utils;

with Pixmaps_IDE; use Pixmaps_IDE;
with Gdk.Pixmap; use Gdk.Pixmap;
with Gdk.Color;  use Gdk.Color;

with Aunit_Filters; use Aunit_Filters;
with Gtkada.Handlers; use Gtkada.Handlers;
with Gtkada.Types; use Gtkada.Types;

package body Make_Harness_Window_Pkg.Callbacks is
   --  Callbacks for main "AUnit_Make_Harness" window. Template
   --  generated by Glade

   use Gtk.Arguments;

   -----------------------
   -- Local subprograms --
   -----------------------

   procedure On_Ok_Button_Clicked
     (Object : access Gtk_Widget_Record'Class);

   procedure On_Cancel_Button_Clicked
     (Object : access Gtk_Widget_Record'Class);

   ---------------------------------------
   -- On_Make_Harness_Window_Delete_Event --
   ---------------------------------------

   function On_Make_Harness_Window_Delete_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean is
   begin
      Hide (Get_Toplevel (Object));
      Main_Quit;
      return True;
   end On_Make_Harness_Window_Delete_Event;

   ---------------------------------
   -- On_Procedure_Entry_Activate --
   ---------------------------------

   procedure On_Procedure_Entry_Activate
     (Object : access Gtk_Entry_Record'Class)
   is
      --  Initialize and set default focus
      Win : constant Make_Harness_Window_Access :=
        Make_Harness_Window_Access (Get_Toplevel (Object));

   begin
      Grab_Focus (Win.Ok);
   end On_Procedure_Entry_Activate;

   ----------------------------
   -- On_Name_Entry_Activate --
   ----------------------------

   procedure On_Name_Entry_Activate
     (Object : access Gtk_Entry_Record'Class)
   is
      Win : constant Make_Harness_Window_Access :=
        Make_Harness_Window_Access (Get_Toplevel (Object));

   begin
      Grab_Focus (Win.Ok);
   end On_Name_Entry_Activate;

   --------------------------
   -- On_Ok_Button_Clicked --
   --------------------------

   procedure On_Ok_Button_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
      Harness_Window : constant Make_Harness_Window_Access :=
        Make_Harness_Window_Access (Get_Toplevel (Object));

      S              : String := Get_Selection (Harness_Window.Explorer);
      Suite_Name     : String_Access;
      Package_Name   : String_Access;
      Id             : Context_Id :=
        Get_Context_Id (Harness_Window.Statusbar, "messages");
      Message        : Message_Id;
   begin
      Hide (Harness_Window.Explorer);

      if S = "" then
         return;
      end if;

      Get_Suite_Name (S, Package_Name, Suite_Name);

      if Suite_Name /= null
        and then Package_Name /= null
      then
         Harness_Window.Suite_Name := GNAT.OS_Lib.String_Access (Suite_Name);
         Message := Push (Harness_Window.Statusbar,
                          Id,
                          "Found suite : " & Harness_Window.Suite_Name.all);
      else
         Message := Push (Harness_Window.Statusbar,
                          Id,
                          "Warning : no suite was found in that file.");
      end if;

      Set_Text (Harness_Window.File_Name_Entry, S);
   end On_Ok_Button_Clicked;

   ------------------------------
   -- On_Cancel_Button_Clicked --
   ------------------------------

   procedure On_Cancel_Button_Clicked
     (Object : access Gtk_Widget_Record'Class)
   is
      Suite_Window : constant Make_Harness_Window_Access :=
        Make_Harness_Window_Access (Get_Toplevel (Object));
   begin
      Hide (Suite_Window.Explorer);
   end On_Cancel_Button_Clicked;

   -----------------------
   -- On_Browse_Clicked --
   -----------------------

   procedure On_Browse_Clicked
     (Object : access Gtk_Button_Record'Class)
   is
      --  Open explorer window to select suite
      Harness_Window : Make_Harness_Window_Access :=
        Make_Harness_Window_Access (Get_Toplevel (Object));

      --  ??? This is never freed
      Filter_A : Filter_Show_All_Access := new Filter_Show_All;
      Filter_B : Filter_Show_Ada_Access := new Filter_Show_Ada;
      Filter_C : Filter_Show_Suites_Access := new Filter_Show_Suites;

   begin
      if Harness_Window.Explorer = null then
         Create_From_Xpm_D
           (Filter_C.Suite_Pixmap,
            Window => null,
            Colormap => Get_System,
            Mask => Filter_C.Suite_Bitmap,
            Transparent => Null_Color,
            Data => box_xpm);

         Gtk_New (Harness_Window.Explorer, "/", "", "Select test harness");
         Create_From_Xpm_D
           (Filter_B.Spec_Pixmap,
            Window => null,
            Colormap => Get_System,
            Mask => Filter_B.Spec_Bitmap,
            Transparent => Null_Color,
            Data => box_xpm);

         Create_From_Xpm_D
           (Filter_B.Body_Pixmap,
            Window => null,
            Colormap => Get_System,
            Mask => Filter_B.Body_Bitmap,
            Transparent => Null_Color,
            Data => package_xpm);

         Register_Filter (Harness_Window.Explorer, Filter_C);
         Register_Filter (Harness_Window.Explorer, Filter_B);
         Register_Filter (Harness_Window.Explorer, Filter_A);

         Widget_Callback.Object_Connect
           (Get_Ok_Button (Harness_Window.Explorer),
            "clicked",
            Widget_Callback.To_Marshaller (On_Ok_Button_Clicked'Access),
            Gtk_Widget (Harness_Window));
         Widget_Callback.Object_Connect
           (Get_Cancel_Button (Harness_Window.Explorer),
            "clicked",
            Widget_Callback.To_Marshaller (On_Cancel_Button_Clicked'Access),
            Gtk_Widget (Harness_Window));
      end if;

      Show_All (Harness_Window.Explorer);
   end On_Browse_Clicked;

   -------------------
   -- On_Ok_Clicked --
   -------------------

   procedure On_Ok_Clicked (Object : access Gtk_Button_Record'Class) is
      --  Generate harness body source file. Close window and main loop if
      --  successful

      Top            : constant Make_Harness_Window_Access :=
        Make_Harness_Window_Access (Get_Toplevel (Object));
      File           : File_Type;
      Procedure_Name : String := Get_Text (Top.Procedure_Entry);
      File_Name      : String := Get_Text (Top.File_Name_Entry);

   begin
      if Procedure_Name /= "" and then File_Name /= "" then
         Mixed_Case (Procedure_Name);
         Mixed_Case (File_Name);

         if Top.Suite_Name = null then
            Top.Suite_Name := new String' ("");
         end if;

         if Is_Regular_File (To_File_Name (Procedure_Name) & ".adb") then
            if Message_Dialog
              ("File " & To_File_Name (Procedure_Name)
               & ".adb" & " exists. Overwrite?",
               Warning,
               Button_Yes or Button_No,
               Button_No,
               "",
               "Warning !") = Button_No
            then
               return;
            end if;
         end if;

         Ada.Text_IO.Create
           (File, Out_File, To_File_Name (Procedure_Name) & ".adb");
         Put_Line
           (File,
            "with AUnit.Test_Runner;" & ASCII.LF
            & "with " &
            Top.Suite_Name.all & ";"
            & ASCII.LF
            & ASCII.LF
            & "procedure " & Procedure_Name & " is" & ASCII.LF
            & ASCII.LF
            & "   procedure Run is new AUnit.Test_Runner ("
            & Top.Suite_Name.all
            & ");"
            & ASCII.LF
            & ASCII.LF
            & "begin"  & ASCII.LF
            & "   Run;" & ASCII.LF
            & "end " & Procedure_Name & ";");
         Close (File);
         Top.Procedure_Name := new String' (To_Lower (Procedure_Name));
      end if;

      Hide (Top);
      Main_Quit;
   end On_Ok_Clicked;

   -----------------------
   -- On_Cancel_Clicked --
   -----------------------

   procedure On_Cancel_Clicked (Object : access Gtk_Button_Record'Class) is
   begin
      Hide (Get_Toplevel (Object));
      Main_Quit;
   end On_Cancel_Clicked;

end Make_Harness_Window_Pkg.Callbacks;
