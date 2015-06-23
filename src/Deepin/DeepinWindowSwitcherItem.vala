//
//  Copyright (C) 2014 Deepin, Inc.
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
	/**
	 * A container for a clone of the texture of a MetaWindow, a WindowIcon
	 * and a shadow.
	 */
	public class DeepinWindowSwitcherItem : Actor
	{
		public const int PREFER_WIDTH = 300;
		public const int PREFER_HEIGHT = 200;
		const int ICON_PREFER_SIZE = 48;
		const int SHAPE_PADDING = 10;
		const int CLONE_PREFER_RECT_WIDTH = PREFER_WIDTH - SHAPE_PADDING * 2;
		const int CLONE_PREFER_RECT_HEIGHT = PREFER_HEIGHT - SHAPE_PADDING * 2;

		/**
		 * The window was resized and a relayout of the tiling layout may
		 * be sensible right now.
		 */
		public signal void request_reposition ();

		public Meta.Window window { get; construct; }

		uint shadow_update_timeout_id = 0;
		bool enable_shadow = false;

		Actor? clone_container = null; // container for clone to add shadow effect
		Clone? clone = null;
		GtkClutter.Texture window_icon;
		DeepinCssActor shape;

		public DeepinWindowSwitcherItem (Meta.Window window)
		{
			Object (window: window);
		}

		construct
		{
			x_align = ActorAlign.FILL;
			y_align = ActorAlign.FILL;

			window.unmanaged.connect (on_unmanaged);
			window.workspace_changed.connect (on_workspace_changed);
			window.notify["on-all-workspaces"].connect (on_all_workspaces_changed);

			window_icon = new WindowIcon (window, ICON_PREFER_SIZE);
			window_icon.set_pivot_point (0.5f, 0.5f);

			shape = new DeepinCssActor ("deepin-window-switcher-item");
			shape.set_pivot_point (0.5f, 0.5f);

			add_child (window_icon);
			add_child (shape);

			load_clone ();
 		}

		~DeepinWindowSwitcherItem ()
		{
			window.unmanaged.disconnect (on_unmanaged);
			window.workspace_changed.disconnect (on_workspace_changed);
			window.notify["on-all-workspaces"].disconnect (on_all_workspaces_changed);

			if (shadow_update_timeout_id != 0) {
				Source.remove (shadow_update_timeout_id);
			}

#if HAS_MUTTER312
			window.size_changed.disconnect (on_window_size_changed);
#else
			var actor = window.get_compositor_private () as WindowActor;
			if (actor != null) {
				actor.size_changed.disconnect (on_window_size_changed);
			}
#endif
		}

		/**
		 * The window unmanaged by the compositor, so we need to destroy ourselves too.
		 */
		void on_unmanaged ()
		{
			if (clone_container != null) {
				clone_container.destroy ();
			}

			if (shadow_update_timeout_id != 0) {
				Source.remove (shadow_update_timeout_id);
				shadow_update_timeout_id = 0;
			}

			destroy ();
		}

		void on_workspace_changed ()
		{
			check_is_window_in_active_workspace ();
		}

		void on_all_workspaces_changed ()
		{
			check_is_window_in_active_workspace ();
		}

		void check_is_window_in_active_workspace ()
		{
			// we don't display windows that are moved to other workspace
			if (!DeepinUtils.is_window_in_tab_list (window)) {
				on_unmanaged ();
			}
		}

		void on_window_size_changed () {
			request_reposition ();
		}

		/**
		 * Waits for the texture of a new WindowActor to be available
		 * and makes a close of it. If it was already was assigned a slot
		 * at this point it will animate to it. Otherwise it will just place
		 * itself at the location of the original window. Also adds the shadow
		 * effect and makes sure the shadow is updated on size changes.
		 */
		void load_clone ()
		{
			var actor = window.get_compositor_private () as WindowActor;
			if (actor == null) {
				Idle.add (() => {
					if (window.get_compositor_private () != null) {
						load_clone ();
					}
					return false;
				});

				return;
			}

			clone_container = new Actor ();
			clone = new Clone (actor.get_texture ());
			clone.add_constraint (new BindConstraint (clone_container, BindCoordinate.SIZE, 0));
			clone_container.add_child (clone);

			add_child (clone_container);

			set_child_below_sibling (shape, clone_container);
			set_child_above_sibling (window_icon, clone_container);

#if HAS_MUTTER312
			window.size_changed.connect (on_window_size_changed);
#else
			actor.size_changed.connect (on_window_size_changed);
#endif
		}

		Meta.Rectangle get_window_outer_rect ()
		{
#if HAS_MUTTER312
			var outer_rect = window.get_frame_rect ();
#else
			var outer_rect = window.get_outer_rect ();
#endif
			return outer_rect;
		}
		/**
		 * Calculate the preferred size of clone.
		 */
		void get_clone_preferred_size (out float width, out float height)
		{
			var outer_rect = get_window_outer_rect ();
			var scale_x = CLONE_PREFER_RECT_WIDTH / (float) outer_rect.width;
			var scale_y = CLONE_PREFER_RECT_HEIGHT / (float) outer_rect.height;
			var scale = Math.fminf (scale_x, scale_y);

			width = outer_rect.width * scale;
			height = outer_rect.height * scale;
		}

		void update_shadow_async (uint interval, int width, int height) {
			if (shadow_update_timeout_id != 0) {
				Source.remove (shadow_update_timeout_id);
				shadow_update_timeout_id = 0;
			}

			shadow_update_timeout_id = Timeout.add (interval, () => {
				do_update_shadow (width, height);
				shadow_update_timeout_id = 0;
				return false;
			});

		}
		void do_update_shadow (int width, int height) {
			if (clone_container == null) {
				return;
			}

			var shadow_effect = clone_container.get_effect ("shadow") as ShadowEffect;
			if (shadow_effect == null) {
				shadow_effect = new ShadowEffect (width, height, 40, 5);
				clone_container.add_effect_with_name ("shadow", shadow_effect);
			} else {
				shadow_effect.update_size (width, height);
			}
		}

		/**
		 * Except for the texture clone and the highlight all children are placed
		 * according to their given allocations. The first two are placed in a way
		 * that compensates for invisible borders of the texture.
		 */
		public override void allocate (ActorBox box, AllocationFlags flags)
		{
			base.allocate (box, flags);

			var scale = box.get_width () / PREFER_WIDTH;

			var shape_box = ActorBox ();
			shape_box.set_size (box.get_width (), box.get_height ());
			shape_box.set_origin (0, 0);
			shape.allocate (shape_box, flags);

			var icon_box = ActorBox ();
			if (box.get_width () <= ICON_PREFER_SIZE * 2.5f) {
				if (box.get_width () >= ICON_PREFER_SIZE) {
					icon_box.set_size (ICON_PREFER_SIZE, ICON_PREFER_SIZE);
				} else {
					float icon_size = Math.fminf (box.get_width (), box.get_height ());
					if (icon_size > SHAPE_PADDING * 2 * scale) {
						icon_size -= SHAPE_PADDING * 2 * scale;
					}
					icon_box.set_size (icon_size, icon_size);
				}
				icon_box.set_origin ((box.get_width () - icon_box.get_width ()) / 2, (box.get_height () - icon_box.get_height ()) / 2);
			} else {
				icon_box.set_size (ICON_PREFER_SIZE, ICON_PREFER_SIZE);
				icon_box.set_origin ((box.get_width () - icon_box.get_width ()) / 2, box.get_height () - icon_box.get_height () - icon_box.get_height () * 0.25f);
			}
			window_icon.allocate (icon_box, flags);

			// if actor's size is really small, just show icon only
			if (box.get_width () <= ICON_PREFER_SIZE * 1.75f) {
				if (clone_container != null) {
					// set clone visible to false manually to hide shadow
					// effect
					clone_container.visible = false;
				}
				return;
			}

			if (clone_container == null) {
				return;
			}

			clone_container.visible = true; // reset clone visible

			var clone_box = ActorBox ();
			float clone_width, clone_height;
			float clone_prefer_width, clone_prefer_height;
			get_clone_preferred_size (out clone_prefer_width, out clone_prefer_height);
			clone_width = clone_prefer_width * scale;
			clone_height = clone_prefer_height * scale;
			clone_box.set_size (clone_width, clone_height);
			clone_box.set_origin ((box.get_width () - clone_box.get_width ()) / 2, (box.get_height () - clone_box.get_height ()) / 2);

			clone_container.allocate (clone_box, flags);

			if (enable_shadow) {
				update_shadow_async (0, (int) clone_width, (int) clone_height);
			}
		}

		public void select (bool value, bool animate = true)
		{
			shape.save_easing_state ();

			shape.set_easing_duration (animate ? 280 : 0);
			shape.set_easing_mode (AnimationMode.EASE_IN_OUT_QUAD);
			shape.select = value;

			if (value) {
				shape.scale_x = 1.033;
				shape.scale_y = 1.033;
			} else {
				shape.scale_x = 1.0;
				shape.scale_y = 1.0;
			}

			shape.restore_easing_state ();
		}
	}
}