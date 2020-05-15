"""
This test checks that renaming an entity across multiple fine
works fine through LSP and clangd.
"""

import GPS
from gs_utils.internal.utils import *


@run_test_driver
def run_test():
    buf = GPS.EditorBuffer.get(GPS.File("my_class.hh"))
    view = buf.current_view()
    view.goto(buf.at(1, 7))
    yield wait_idle()

    yield idle_modal_dialog(
        lambda: GPS.execute_action("rename entity"))
    new_name_ent = get_widget_by_name("new_name")
    new_name_ent.set_text("Dummy")
    dialog = get_window_by_title("Renaming entity")
    check = get_button_from_label("Automatically save modified files", dialog)
    check.set_active(False)
    get_stock_button(dialog, Gtk.STOCK_OK).clicked()

    yield hook('language_server_response_processed')

    gps_assert(dump_locations_tree(),
               ['Refactoring - rename My_Class to Dummy (3 items in 2 files)',
                ['my_class.hh (2 items)',
                 ['<b>9:3</b>       entity processed',
                  '<b>1:7</b>       entity processed'],
                 'main.cpp (1 item)',
                 ['<b>10:3</b>      entity processed']]],
               "wrong location tree")
