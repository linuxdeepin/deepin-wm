//
//  Copyright (C) 2014 Deepin, Inc.
//  Copyright (C) 2014 Tom Beckmann
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

using Clutter;
using Meta;

namespace Gala
{
	// TODO: description
	/**
	 * This is the container which manages a clone of the background
	 * which will be scaled and animated inwards, a
	 * DeepinWindowCloneFlowContainer for the windows on this workspace
	 * and also holds the instance for the DeepinWorkspaceThumbClone.
	 * The latter is not added to the DeepinWorkspaceFlowClone itself
	 * though but to a container of the DeepinMultitaskingView.
	 */
	public class DeepinWorkspaceFlowClone : Actor
	{
		/**
		 * The offset of the scaled background to the bottom of the monitor bounds
		 */
		// TODO:
		public const int BOTTOM_OFFSET = 20;

		/**
		 * The offset of the scaled background to the top of the monitor bounds
		 */
		// TODO:
		const int TOP_OFFSET = 200;

		/**
		 * The amount of time a window has to be over the DeepinWorkspaceFlowClone while in drag
		 * before we activate the workspace.
		 */
		const int HOVER_ACTIVATE_DELAY = 400;

		/**
		 * A window has been selected, the DeepinMultitaskingView should consider activating
		 * and closing the view.
		 */
		public signal void window_activated (Window window);

		/**
		 * The background has been selected. Switch to that workspace.
		 *
		 * @param close_view If the DeepinMultitaskingView should also consider closing itself
		 *                   after switching.
		 */
		public signal void selected (bool close_view);

		public Workspace workspace { get; construct; }
		public DeepinWindowCloneFlowContainer window_container { get; private set; }

		/**
		 * Own the related thumbnail workspace clone so that signals
		 * and events could be dispatched easily.
		 */
		public DeepinWorkspaceThumbClone related_thumb_workspace { get; private set; }

#if HAS_MUTTER314
		BackgroundManager background;
#else
		Background background;
#endif
		bool opened;

		uint hover_activate_timeout = 0;

		public DeepinWorkspaceFlowClone (Workspace workspace)
		{
			Object (workspace: workspace);
		}

		construct
		{
			opened = false;

			unowned Screen screen = workspace.get_screen ();
			var monitor_geometry = screen.get_monitor_geometry (screen.get_primary_monitor ());

			background = new DeepinFramedBackground (workspace.get_screen ());
			background.reactive = true;
			background.button_press_event.connect (() => {
				selected (true);
				return false;
			});

			related_thumb_workspace = new DeepinWorkspaceThumbClone (workspace);
			related_thumb_workspace.selected.connect (() => {
				if (workspace != screen.get_active_workspace ()) {
					selected (false);
				}
			});

			window_container = new DeepinWindowCloneFlowContainer ();
			window_container.window_activated.connect ((w) => {
					window_activated (w);
			});
			window_container.window_selected.connect ((w) => {
					related_thumb_workspace.select_window (w);
			});
			window_container.width = monitor_geometry.width;
			window_container.height = monitor_geometry.height;
			screen.restacked.connect (window_container.restack_windows);

			var thumb_drop_action = new DragDropAction (DragDropActionType.DESTINATION, "deepin-multitaskingview-window");
			related_thumb_workspace.add_action (thumb_drop_action);

			var background_drop_action = new DragDropAction (DragDropActionType.DESTINATION, "deepin-multitaskingview-window");
			background.add_action (background_drop_action);
			background_drop_action.crossed.connect ((hovered) => {
				if (!hovered && hover_activate_timeout != 0) {
					Source.remove (hover_activate_timeout);
					hover_activate_timeout = 0;
					return;
				}

				if (hovered && hover_activate_timeout == 0) {
					hover_activate_timeout = Timeout.add (HOVER_ACTIVATE_DELAY, () => {
						selected (false);
						hover_activate_timeout = 0;
						return false;
					});
				}
			});

			screen.window_entered_monitor.connect (window_entered_monitor);
			screen.window_left_monitor.connect (window_left_monitor);
			workspace.window_added.connect (add_window);
			workspace.window_removed.connect (remove_window);

			add_child (background);
			add_child (window_container);

			// add existing windows
			var windows = workspace.list_windows ();
			foreach (var window in windows) {
				if (window.window_type == WindowType.NORMAL
					&& !window.on_all_workspaces
					&& window.get_monitor () == screen.get_primary_monitor ()) {
					window_container.add_window (window);
					related_thumb_workspace.add_window (window);
				}
			}

			var listener = WindowListener.get_default ();
			listener.window_no_longer_on_all_workspaces.connect (add_window);
		}

		~DeepinWorkspaceFlowClone ()
		{
			unowned Screen screen = workspace.get_screen ();

			screen.restacked.disconnect (window_container.restack_windows);

			screen.window_entered_monitor.disconnect (window_entered_monitor);
			screen.window_left_monitor.disconnect (window_left_monitor);
			workspace.window_added.disconnect (add_window);
			workspace.window_removed.disconnect (remove_window);

			var listener = WindowListener.get_default ();
			listener.window_no_longer_on_all_workspaces.disconnect (add_window);

			background.destroy ();
		}

		/**
		 * Add a window to the DeepinWindowCloneFlowContainer and the DeepinWorkspaceThumbClone if it really
		 * belongs to this workspace and this monitor.
		 */
		void add_window (Window window)
		{
			if (window.window_type != WindowType.NORMAL
				|| window.get_workspace () != workspace
				|| window.on_all_workspaces
				|| window.get_monitor () != window.get_screen ().get_primary_monitor ())
				return;

			foreach (var child in window_container.get_children ())
				if (((DeepinWindowClone) child).window == window)
					return;

			window_container.add_window (window);
			related_thumb_workspace.add_window (window);
		}

		/**
		 * Remove a window from the DeepinWindowCloneFlowContainer and the DeepinWorkspaceThumbClone
		 */
		void remove_window (Window window)
		{
			window_container.remove_window (window);
			// TODO: animate
			related_thumb_workspace.remove_window (window);
		}

		void window_entered_monitor (Screen screen, int monitor, Window window)
		{
			add_window (window);
		}

		void window_left_monitor (Screen screen, int monitor, Window window)
		{
			if (monitor == screen.get_primary_monitor ())
				remove_window (window);
		}

		/**
		 * Utility function to shrink a MetaRectangle on all sides for the given amount.
		 * Negative amounts will scale it instead.
		 *
		 * @param amount The amount in px to shrink.
		 */
		static inline void shrink_rectangle (ref Meta.Rectangle rect, int amount)
		{
			rect.x += amount;
			rect.y += amount;
			rect.width -= amount * 2;
			rect.height -= amount * 2;
		}

		/**
		 * Animates the background to its scale, causes a redraw on the DeepinWorkspaceThumbClone and
		 * makes sure the DeepinWindowCloneFlowContainer animates its windows to their tiled layout.
		 * Also sets the current_window of the DeepinWindowCloneFlowContainer to the active window
		 * if it belongs to this workspace.
		 */
		public void open ()
		{
			if (opened)
				return;

			opened = true;

			var screen = workspace.get_screen ();
			var display = screen.get_display ();

			var monitor = screen.get_monitor_geometry (screen.get_primary_monitor ());
			var scale = (float)(monitor.height - TOP_OFFSET - BOTTOM_OFFSET) / monitor.height;
			var pivotY = TOP_OFFSET / (monitor.height - monitor.height * scale);
			background.set_pivot_point (0.5f, pivotY);

			background.save_easing_state ();
			background.set_easing_duration (250);
			background.set_easing_mode (AnimationMode.EASE_OUT_QUAD);
			background.set_scale (scale, scale);
			background.restore_easing_state ();

			Meta.Rectangle area = {
				(int)Math.floorf (monitor.x + monitor.width - monitor.width * scale) / 2,
				(int)Math.floorf (monitor.y + TOP_OFFSET),
				(int)Math.floorf (monitor.width * scale),
				(int)Math.floorf (monitor.height * scale)
			};
			shrink_rectangle (ref area, 32);

			window_container.padding_top = TOP_OFFSET;
			window_container.padding_left =
				window_container.padding_right = (int)(monitor.width - monitor.width * scale) / 2;
			window_container.padding_bottom = BOTTOM_OFFSET;

			window_container.open (screen.get_active_workspace () == workspace ? display.get_focus_window () : null);
		}

		/**
		 * Close the view again by animating the background back to its scale and
		 * the windows back to their old locations.
		 */
		public void close ()
		{
			if (!opened)
				return;

			opened = false;

			background.save_easing_state ();
			background.set_easing_duration (300);
			background.set_easing_mode (AnimationMode.EASE_IN_OUT_CUBIC);
			background.set_scale (1, 1);
			background.restore_easing_state ();

			window_container.close ();
		}
	}
}