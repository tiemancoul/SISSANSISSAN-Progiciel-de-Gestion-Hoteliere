<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Hotel;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/** Platform-level hotel management, reserved to the SaaS super admin. */
class HotelController extends Controller
{
    public function index(Request $request)
    {
        abort_unless($request->user()->isSuperAdmin(), 403);

        return Hotel::orderBy('name')->get();
    }

    public function store(Request $request)
    {
        abort_unless($request->user()->isSuperAdmin(), 403);

        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'slug' => ['required', 'alpha_dash', 'max:100', 'unique:hotels'],
        ]);

        return response()->json(Hotel::create($data), 201);
    }

    public function update(Request $request, Hotel $hotel)
    {
        abort_unless($request->user()->isSuperAdmin(), 403);

        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'slug' => ['sometimes', 'alpha_dash', 'max:100', Rule::unique('hotels')->ignore($hotel)],
            'is_active' => ['sometimes', 'boolean'],
        ]);
        $hotel->update($data);

        return $hotel;
    }
}
