<?php

namespace App\Http\Controllers\Api;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\Rules\Password;

/** Staff accounts of the current user's hotel. A hotel admin only ever sees their own hotel. */
class UserController extends Controller
{
    public function index(Request $request)
    {
        $this->authorizeManager($request);

        return $this->scoped($request)->orderBy('name')->get();
    }

    public function store(Request $request)
    {
        $this->authorizeManager($request);
        $actor = $request->user();

        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'max:255', 'unique:users'],
            'password' => ['required', Password::min(8)],
            // Super admins are created out of band, never through the API.
            'role' => ['required', Rule::enum(Role::class)->except([Role::SuperAdmin])],
            'hotel_id' => [Rule::requiredIf($actor->isSuperAdmin()), 'exists:hotels,id'],
        ]);

        $user = new User($data);
        // hotel_id is never mass-assigned: a hotel admin always creates staff in their own hotel.
        $user->hotel_id = $actor->isSuperAdmin() ? $data['hotel_id'] : $actor->hotel_id;
        $user->save();

        return response()->json($user, 201);
    }

    public function update(Request $request, int $id)
    {
        $this->authorizeManager($request);
        // Looked up through the scope so another hotel's user is a 404, not a 403 that confirms it exists.
        $user = $this->scoped($request)->findOrFail($id);

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'email' => ['sometimes', 'email', 'max:255', Rule::unique('users')->ignore($user)],
            'password' => ['sometimes', Password::min(8)],
            'role' => ['sometimes', Rule::enum(Role::class)->except([Role::SuperAdmin])],
            'is_active' => ['sometimes', 'boolean'],
        ]);
        $user->update($data);

        if (! $user->is_active) {
            $user->tokens()->delete();
        }

        return $user;
    }

    private function authorizeManager(Request $request): void
    {
        abort_unless(in_array($request->user()->role, [Role::SuperAdmin, Role::HotelAdmin], true), 403);
    }

    private function scoped(Request $request)
    {
        $actor = $request->user();

        return $actor->isSuperAdmin() ? User::query() : User::where('hotel_id', $actor->hotel_id);
    }
}
